/*
 * "Hist_Acc" software
 *
 * This program creates descriptors and uses them to communicate with hardware
 * which accelerates calculations of histogram on part of the picture.
 *
 */

#include "stdio.h"
#include "stdlib.h"
#include "io.h"
#include "system.h"
#include "alt_types.h"
#include "altera_avalon_sgdma.h"
#include "altera_avalon_sgdma_regs.h"
#include "altera_avalon_performance_counter.h"
#include "sys/alt_cache.h"
#include "includes.h"

#define NUMBER_OF_BUFFERS 512	//for the whole image
#define BUFFER_LENGTH 512	//for the whole image

void transmit_callback_function(void * context)
{
	alt_u16 *tx_done = (alt_u16*) context;
	(*tx_done)++;  /* main will be polling for this value being 1 */
}

void receive_callback_function(void * context)
{
	alt_u16 *rx_done = (alt_u16*) context;
	(*rx_done)++;  /* main will be polling for this value being 1 */
}

int main()
{
	/* Pointers to devices - initialization*/
	alt_sgdma_dev *sgdma_m2s = alt_avalon_sgdma_open("/dev/sgdma_m2s");
	alt_sgdma_dev *sgdma_s2m = alt_avalon_sgdma_open("/dev/sgdma_s2m");

	/**************************************************************
	* Making sure the SG-DMAs were opened correctly            *
	************************************************************/
	if(sgdma_m2s == NULL)
	{
		printf("Could not open the transmit SG-DMA\n");
		return 1;
	}
	if(sgdma_s2m == NULL)
	{
		printf("Could not open the receive SG-DMA\n");
		return 1;
	}	
	
	/* Descriptors and their copies - initialization*/
	void * temp_ptr;
	alt_sgdma_descriptor *m2s_desc, *m2s_desc_copy;
	alt_sgdma_descriptor *s2m_desc, *s2m_desc_copy;

	/* Variables used to check if TX/RX process is done - initialization*/
	volatile alt_u16 tx_done = 0;
	volatile alt_u16 rx_done = 0;

	/* Counters - initialization*/
	alt_u32 buffer_counter, contents_counter;
	alt_u32 temp_cnt = 0;

	/* Buffers used for input and output data - initialization*/
	alt_8  ** data_buffers  = (alt_8  **) malloc(NUMBER_OF_BUFFERS * sizeof(alt_8 *));
	alt_16 ** result_buffers = (alt_16 **) malloc(NUMBER_OF_BUFFERS * sizeof(alt_16 *));
	alt_u16 * buffer_lengths = (alt_u16 *) malloc(NUMBER_OF_BUFFERS * sizeof(alt_u16));

	/* Variables used in loops - initialization*/
	alt_u32 i = 0, l = 0;

	/* Positions of corner pixels of rectangle in the picture on which the contrast is going to be done */
	unsigned long mtl = 0, mbr = 511, ntl = 0, nbr = 511;
	
	/* Sizes of rectangle sides - initialization*/
	unsigned long P =0, Q = 0;
	
	/* Histogram initialization*/
	unsigned long hist[256]={0};
	unsigned long hist_part[256]={0};

	/* Cumulative histogram initialization*/
	unsigned long cumhist[256]={0};
	unsigned long cumhist_part[256]={0};	
	
	/* Width and height of input picture - initialization*/
	unsigned long  width = 0, height = 0;

	/* Pointers to file, all pixels of input image and all pixels of output image*/
	unsigned char *input_image;
	alt_u32 *ram_buffer;
	unsigned char *y, *z;
	FILE* fp;

	/* Instead of bright64.bin available binary files are:
	 * bright512.bin, dark64.bin, dark512.bin, low_contrast64.bin, low_contrast512.bin 	*/
	fp = fopen("/mnt/host/bright512.bin", "rb");

	if (fp == NULL)
		printf("\n The file could not be opened!");

	/* First 4 bytes represents the width of a picture*/
	fread(&width, 4, 1, fp);

	/* Second 4 bytes represents the height of a picture*/
	fread(&height, 4, 1, fp);

	/* Allocating memory for input image*/
	input_image = (unsigned char*) malloc(width*height);
	
	/* Allocating memory for histogram - ram content*/
	ram_buffer = (alt_u32*) malloc(256);

	/* Allocating memory for output image*/
	y = (unsigned char*) malloc(width*height);

	/* Allocating memory for output image*/
	z = (unsigned char*) malloc(width*height);

	/* Coping image pixels to input_image array*/
	fread(input_image, 1, width*height, fp);
	fclose(fp);

	int return_code = 0;
	
	/* Sizes of rectangle sides*/
	P = mbr - mtl + 1;
	Q = nbr - ntl + 1;
	
	/**************************************************************
	* Allocation of the transmit descriptors                   *
	* - First allocate a large buffer to the temporary pointer *
	* - Second check for successful memory allocation          *
	* - Third put this memory location into the pointer copy   *
	*   to be freed before the program exits                   *
	* - Forth slide the temporary pointer until it lies on a 32*
	*   byte boundary (descriptor master is 256 bits wide)     * 
	************************************************************/  
	temp_ptr = malloc((NUMBER_OF_BUFFERS + 2) * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if(temp_ptr == NULL)
	{
		printf("Failed to allocate memory for the transmit descriptors\n");
		return 1; 
	}
	m2s_desc_copy = (alt_sgdma_descriptor *)temp_ptr;
  
	while((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	m2s_desc = (alt_sgdma_descriptor *)temp_ptr;
	m2s_desc[NUMBER_OF_BUFFERS].control = 0;
	/**************************************************************/

	for (i = 0; i < NUMBER_OF_BUFFERS; i++){																//zameniti sa height
    	alt_avalon_sgdma_construct_mem_to_stream_desc(&m2s_desc[i],
    			                                      &m2s_desc[i+1],
    			                                      (alt_u32*)&input_image[(mtl+i)*BUFFER_LENGTH+ntl], 	//ovde obican width(cele slike)
    			                                      (alt_u16)BUFFER_LENGTH,								//ovde width dela slike
    			                                      0,
    			                                      0,
    			                                      0,
    			                                      0);

    }
	
	/**************************************************************
	* Allocation of the receive descriptors                    *
	* - First allocate a large buffer to the temporary pointer *
	* - Second check for successful memory allocation          *
	* - Third put this memory location into the pointer copy   *
	*   to be freed before the program exits                   *
	* - Forth slide the temporary pointer until it lies on a 32*
	*   byte boundary (descriptor master is 256 bits wide)     * 
	************************************************************/  
	temp_ptr = malloc(3 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if(temp_ptr == NULL)
	{
		printf("Failed to allocate memory for the receive descriptors\n");
		return 1; 
	}
	s2m_desc_copy = (alt_sgdma_descriptor *)temp_ptr;

	while((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	s2m_desc = (alt_sgdma_descriptor *)temp_ptr;
	/**************************************************************/

	/* Clear out the null descriptor owned by hardware bit.  These locations
	* came from the heap so we don't know what state the bytes are in (owned bit could be high).*/
	s2m_desc[1].control = 0;

	alt_avalon_sgdma_construct_stream_to_mem_desc(&s2m_desc[0],
												  &s2m_desc[1],
												  (alt_u32*)&ram_buffer,
												  (alt_u16)256,
												  0);
	
/*
	return_code = create_descriptors(&m2s_desc,
								&m2s_desc_copy,
								&s2m_desc,
								&s2m_desc_copy,
								data_buffers,
								result_buffers,
								buffer_lengths,
								P);

	if(return_code == 1)
	{
		printf("Allocating the data buffers failed... exiting\n");
		return 1;
	}
*/
	/**************************************************************
	* Register the ISRs that will get called when each (full)  *
	* transfer completes. When park bit is set, processed      *
	* descriptors are not invalidated (OWNED_BY_HW bit stays 1)*
	* meaning that the same descriptors can be used for new    *
	* transfers.                                               *
	************************************************************/
	alt_avalon_sgdma_register_callback(sgdma_m2s,
									&transmit_callback_function,
									(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_PARK_MSK),
									(void*)&rx_done);

	alt_avalon_sgdma_register_callback(sgdma_s2m,
									&receive_callback_function,
									(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_PARK_MSK),
								   (void*)&tx_done);
	/**************************************************************/
	
	/*  Initialization of the buffer memories and the transmit+receive descriptors */
	  for(buffer_counter = 0; buffer_counter < P; buffer_counter++)
	  {
		  buffer_lengths[buffer_counter] = Q;

		  data_buffers[buffer_counter] = (alt_8 *)malloc(Q * sizeof(alt_8));
		  if(data_buffers[buffer_counter] == NULL)
		  {
			printf("Allocating a transmit buffer region failed\n");
			return 1;
		  }

		  result_buffers[buffer_counter] = (alt_16 *)malloc(Q * sizeof(alt_16));
		  if(result_buffers[buffer_counter] == NULL)
		  {
			printf("Allocating a receive buffer region failed\n");
			return 1;
		  }

		  for(contents_counter = 0; contents_counter < Q; contents_counter++)
		  {
			data_buffers[buffer_counter][contents_counter] = (alt_8)(*(input_image + temp_cnt));
			result_buffers[buffer_counter][contents_counter] = 0;
			temp_cnt++;
		  }
	  }
	  
/*
    return_code = linear_function_hw(sgdma_m2s,
    		                         m2s_desc,
    		                         &tx_done,
    		                         sgdma_s2m,
    		                         s2m_desc,
    		                         &rx_done);

	if(return_code == 1)
	{
		printf("Allocating the data buffers failed... exiting\n");
		return 1;
	}
*/
	for (i = 0; i < BUFFER_LENGTH; i++) {
		for(contents_counter = 0; contents_counter < BUFFER_LENGTH; contents_counter++)
				  {
					*(y + i * BUFFER_LENGTH + contents_counter) = (alt_8) result_buffers[i][contents_counter];
				  }
	}

	/* Output image is written in binary file  */
	fp = fopen("/mnt/host/bright512_hw_ram.bin", "wb");

	/* Four bytes for width*/
	fwrite(&width, 4, 1, fp);

	/* Four bytes for height*/
	fwrite(&height, 4, 1, fp);

	/* Rest of output image*/
	fwrite(y, 1, width*height, fp);

	fclose(fp);
/*
	for (i = 0; i < BUFFER_LENGTH; i++) {
		for(contents_counter = 0; contents_counter < BUFFER_LENGTH; contents_counter++)
				  {
					*(z + i * BUFFER_LENGTH + contents_counter) = (alt_8) data_buffers[i][contents_counter];
				  }
	}*/

	/* Output image is written in binary file  */
	//fp = fopen("/mnt/host/bright512_ulaz.bin", "wb");

	/* Four bytes for width*/
	//fwrite(&width, 4, 1, fp);

	/* Four bytes for height*/
	//fwrite(&height, 4, 1, fp);

	/* Rest of output image*/
	//fwrite(z, 1, width*height, fp);

	//fclose(fp);

	/**************************************************************
	* Free allocated memory buffers.						      *
	************************************************************/
	for (i = 0; i < P; i++)
	{
		free(data_buffers[i]);
		free(result_buffers[i]);
	}

	free(data_buffers);
	free(result_buffers);

	free(m2s_desc_copy);
	free(s2m_desc_copy);
	/**************************************************************/


	printf("Exiting...");
	return 0;
}
