/*
 * "DVS_sys" software
 *
 * This program creates descriptors and uses them to communicate with hardware
 * which accelerates calculations of histogram on part of the picture and sends
 * it back to software which later uses that histogram to make cumulative histogram.
 * After that software sends it again to hardware which uses cumhist as LUT in
 * order to accelerate process of making a picture with better contrast. Hardware
 * only swaps the pixel from original picture with its corresponding value from
 * cumhist LUT.
 *
 */

#include "stdio.h"
#include "stdlib.h"
#include "math.h"
#include "io.h"
#include "system.h"
#include "alt_types.h"
#include "altera_avalon_sgdma.h"
#include "altera_avalon_sgdma_regs.h"
#include "altera_avalon_performance_counter.h"
#include "sys/alt_cache.h"

/*
 * set to 1 to see debug messages.
 */
#define DEBUG 	0

/*
 * address definitions
 */
#define STATUS_ADDRESS  0x00
#define CONTROL_ADDRESS 0x01
#define NOP_LOW_ADDRESS 0x02
#define NOP_MIDDLE_ADDRESS 0x03
#define NOP_HIGH_ADDRESS 0x04
#define CUMHIST_ADDRESS 0x5

/*
 * control bits definitions
 */
#define RUN		(1 << 7)
#define RESET 	(1 << 6)
#define CONF	(1 << 5)
#define PROCESS (1 << 4)

volatile alt_u8 tx_done = 0;
volatile alt_u8 rx_done = 0;


//Pointers to file, all pixels of input image and all pixels of output image
alt_u8 *input_image;
alt_u8 *output_image;

void transmit_callback_function(void * context)
{
	tx_done = 1;
#if DEBUG
	printf("Tx done\n");
#endif
}

void receive_callback_function(void * context)
{
	rx_done = 1;
#if DEBUG
	printf("Rx done\n");
#endif
}


int main()
{
	alt_u32  nop = 0;

	alt_u32 i = 0;

	/*
	 * Positions of corner pixels of rectangle in the picture on which the contrast is going to be done
	 */
	alt_u32 mtl = 0, mbr = 1, ntl = 0, nbr = 1;

	/*
	 * Width and height of input picture - initialization
	 */
	alt_u32  width = 0, height = 0;

	/*
	 * Values of number of pixel bytes later to be combined to total number of pixels in hardware.
	 * Hardware sees these values as three eight bit values.
	 */
	alt_u32 nop_low = 0;
	alt_u32 nop_middle = 0;
	alt_u32 nop_high = 0;

	/*
	 * Cumulative histogram array will be stored here
	 */
	alt_u8 cumhist[256] = {0};

	/*
	 * Positions of corner pixels of rectangle in the picture on which the contrast is going to be done
	 */
	printf("Enter x position of top left pixel:\n");
	scanf("%lu", &mtl);

	printf("Enter y position of top left pixel:\n");
	scanf("%lu", &ntl);

	printf("Enter x position of bottom right pixel:\n");
	scanf("%lu", &mbr);

	printf("Enter y position of bottom right pixel:\n");
	scanf("%lu", &nbr);

	/*
	 * Sizes of rectangle sides - initialization
	 */
	alt_u32 P =0, Q = 0;

	/*
	 * Histogram initialization
	 */
	alt_u16 hist[256]={0};

	FILE* fp;

	/*
	 * Instead of bright64.bin available binary files are:
	 * bright512.bin, dark64.bin, dark512.bin, low_contrast64.bin, low_contrast512.bin
	 */
	fp = fopen("/mnt/host/dark512.bin", "rb");

	/*
	 * First 4 bytes represents the width of a picture
	 */
	fread(&width, 4, 1, fp);

	/*
	 * Second 4 bytes represents the height of a picture
	 */
	fread(&height, 4, 1, fp);

	/*
	 * Allocating memory for input image
	 */
	input_image = (unsigned char*) malloc(width*height);

	/*
	 * Allocating memory for input image
	 */
	output_image = (unsigned char*) malloc(width*height);

	/*
	 * Coping image pixels to input_image array
	 */
	printf("Reading input image pixels ...\n");
	fread(input_image, 1, width*height, fp);
	printf("Input image loaded!\n");
	fclose(fp);

	int return_code = 0;

	/*
	 * Sizes of rectangle sides
	 */
	P = mbr - mtl + 1;
	Q = nbr - ntl + 1;

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

	temp_ptr = malloc((Q + 2) * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
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
	/*
	 * Clear out the null descriptor owned by hardware bit.  These locations
	 * came from the heap so we don't know what state the bytes are in (owned bit could be high).
	 */
	m2s_desc[Q].control = 0;


	temp_ptr = malloc(3 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL)
	{
		printf("\nFailed to allocate memory for the receive descriptors\n");
		return 1;
	}
	s2m_desc_copy = (alt_sgdma_descriptor *)temp_ptr;

	while ((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	s2m_desc = (alt_sgdma_descriptor *)temp_ptr;

	s2m_desc[1].control = 0;

	for (alt_u32 i = 0; i < Q; i++)
		alt_avalon_sgdma_construct_mem_to_stream_desc(
							&m2s_desc[i],  // current descriptor pointer
						    &m2s_desc[i+1], // next descriptor pointer
							(alt_u32*)&input_image[(mtl+i)*width+ntl],  // read buffer location
						    (alt_u16)P,  // length of the buffer
						    0, // reads are not from a fixed location
						    0, // start of packet is disabled for the Avalon-ST interfaces
						    0, // end of packet is disabled for the Avalon-ST interfaces,
						    0);  // there is only one channel

	alt_avalon_sgdma_construct_stream_to_mem_desc(
							&s2m_desc[0],  // current descriptor pointer
							&s2m_desc[1], // next descriptor pointer
							(alt_u32*)hist,  // write buffer location
							(alt_u16)256*sizeof(alt_16),  // length of the buffer
							0); // writes are not to a fixed location

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

	//Ubaciti proveru za unos brojeva
	nop = P * Q;
	printf("Total number of pixels to be processed =  %lu\n", nop);

	nop_low = nop & 0x000000ff;
	nop_middle = (nop & 0x0000ff00) >> 8;
	nop_high = (nop & 0x00070000) >> 16;

	IOWR_8DIRECT(ACC_HIST_BASE, NOP_LOW_ADDRESS, nop_low);

#if DEBUG
	nop_low = IORD_8DIRECT(ACC_HIST_BASE, NOP_LOW_ADDRESS );
	printf("nop_low = %x\n", nop_low);
#endif

	IOWR_8DIRECT(ACC_HIST_BASE, NOP_MIDDLE_ADDRESS, nop_middle);

#if DEBUG
	nop_middle = IORD_8DIRECT(ACC_HIST_BASE, NOP_MIDDLE_ADDRESS );
	printf("nop_middle = %x\n", nop_middle);
#endif

	IOWR_8DIRECT(ACC_HIST_BASE, NOP_HIGH_ADDRESS, nop_high);

#if DEBUG
	nop_high = IORD_8DIRECT(ACC_HIST_BASE, NOP_HIGH_ADDRESS );
	printf("nop_high = %x\n", nop_high);
#endif

	IOWR_8DIRECT(ACC_HIST_BASE, CONTROL_ADDRESS, RUN);

#if DEBUG
	alt_u8 control_reg = IORD_8DIRECT(ACC_HIST_BASE, CONTROL_ADDRESS );
	printf("control_reg = %x\n", control_reg);

	alt_u8 status_reg = IORD_8DIRECT(ACC_HIST_BASE, STATUS_ADDRESS);
	printf("status_reg = %x\n", status_reg);
#endif

	alt_u32 transmit_status = alt_avalon_sgdma_do_async_transfer(sgdma_m2s, &m2s_desc[0]);
	while(tx_done < 1) {}
	tx_done = 0;

	alt_u32 receive_status = alt_avalon_sgdma_do_async_transfer(sgdma_s2m, &s2m_desc[0]);
	while(rx_done < 1) {}
	rx_done = 0;


	/**************************************************************
	* Stop the SGDMAs                                          *
	************************************************************/
	alt_avalon_sgdma_stop(sgdma_m2s);
	alt_avalon_sgdma_stop(sgdma_s2m);

	/**************************************************************
	* Free allocated memory buffers.						      *
	************************************************************/
	free(m2s_desc_copy);
	free(s2m_desc_copy);
	/**************************************************************/

	IOWR_8DIRECT(CONTRAST_ACC_BASE, NOP_LOW_ADDRESS, nop_low);

#if DEBUG
	nop_low = IORD_8DIRECT(CONTRAST_ACC_BASE, NOP_LOW_ADDRESS );
	printf("contrast_nop_low = %x\n", nop_low);
#endif

	IOWR_8DIRECT(CONTRAST_ACC_BASE, NOP_MIDDLE_ADDRESS, nop_middle);

#if DEBUG
	nop_middle = IORD_8DIRECT(CONTRAST_ACC_BASE, NOP_MIDDLE_ADDRESS );
	printf("contrast_nop_middle = %x\n", nop_middle);
#endif

	IOWR_8DIRECT(CONTRAST_ACC_BASE, NOP_HIGH_ADDRESS, nop_high);

#if DEBUG
	nop_high = IORD_8DIRECT(CONTRAST_ACC_BASE, NOP_HIGH_ADDRESS );
	printf("contrast_nop_high = %x\n", nop_high);
#endif

	IOWR_8DIRECT(CONTRAST_ACC_BASE, CONTROL_ADDRESS, CONF);

#if DEBUG
	alt_u8 contrast_control_reg = IORD_8DIRECT(CONTRAST_ACC_BASE, CONTROL_ADDRESS );
	printf("contrast_control_reg = %x\n", contrast_control_reg);
#endif

	/*
	 * Cumulative histogram calculation
	 */
	alt_u32 cumhist_temp[256] = {0};
	cumhist[0]=round((255*((float)hist[0])/(P*Q)));
	cumhist_temp[0] = cumhist[0];

	for(i=1;i<256;i++)
	{
		cumhist_temp[i] = cumhist_temp[i-1] + hist[i];
		cumhist[i]=round((255*((float)cumhist_temp[i])/(P*Q)));
	}

	alt_sgdma_dev *sgdma_m2s_contrast = alt_avalon_sgdma_open("/dev/sgdma_m2s_contrast");
	alt_sgdma_dev *sgdma_s2m_contrast = alt_avalon_sgdma_open("/dev/sgdma_s2m_contrast");

	if(sgdma_m2s_contrast == NULL)
	{
		printf("Could not open the transmit sgdma_m2s_cumhist\n");
		return 1;
	}

	if(sgdma_s2m_contrast == NULL)
	{
		printf("Could not open the transmit sgdma_s2m_cumhist\n");
		return 1;
	}

	alt_sgdma_descriptor *m2s_desc_contrast, *m2s_desc_contrast_copy;
	alt_sgdma_descriptor *s2m_desc_contrast, *s2m_desc_contrast_copy;

	temp_ptr = malloc(3 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL)
	{
		printf("\nFailed to allocate memory for the receive descriptors\n");
		return 1;
	}
	m2s_desc_contrast_copy = (alt_sgdma_descriptor *)temp_ptr;

	while ((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	m2s_desc_contrast = (alt_sgdma_descriptor *)temp_ptr;
	m2s_desc_contrast[1].control = 0;

	alt_avalon_sgdma_construct_mem_to_stream_desc(
						&m2s_desc_contrast[0],  // current descriptor pointer
						&m2s_desc_contrast[1], // next descriptor pointer
						(alt_u32*)cumhist,  // read buffer location
						(alt_u16)256*sizeof(alt_u8),  // length of the buffer
						0, // reads are not from a fixed location
						0, // start of packet is disabled for the Avalon-ST interfaces
						0, // end of packet is disabled for the Avalon-ST interfaces,
						0);  // there is only one channel

	alt_avalon_sgdma_register_callback(sgdma_m2s_contrast,
									&transmit_callback_function,
									(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_PARK_MSK),
									 NULL);


	transmit_status = alt_avalon_sgdma_do_async_transfer(sgdma_m2s_contrast, &m2s_desc_contrast[0]);

	while (tx_done < 1){}

	tx_done = 0;

	/*
	 * Wait until configuration is done.
	 */
	while ((IORD_8DIRECT(CONTRAST_ACC_BASE, STATUS_ADDRESS) & 0x3C) != 0x10 );

#if DEBUG
	printf("Configuration done!\n");
#endif

	alt_avalon_sgdma_stop(sgdma_m2s_contrast);
	free(m2s_desc_contrast_copy);

	temp_ptr = malloc((Q + 2) * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if(temp_ptr == NULL)
	{
		printf("Failed to allocate memory for the transmit descriptors\n");
		return 1;
	}

	m2s_desc_contrast_copy = (alt_sgdma_descriptor *)temp_ptr;

	while((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	m2s_desc_contrast = (alt_sgdma_descriptor *)temp_ptr;
	m2s_desc_contrast[Q].control = 0;

	temp_ptr = malloc((Q + 2) * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if(temp_ptr == NULL)
	{
		printf("Failed to allocate memory for the transmit descriptors\n");
		return 1;
	}

	s2m_desc_contrast_copy = (alt_sgdma_descriptor *)temp_ptr;

	while((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	s2m_desc_contrast = (alt_sgdma_descriptor *)temp_ptr;
	s2m_desc_contrast[Q].control = 0;

	for (alt_u32 i = 0; i < Q; i++)
		alt_avalon_sgdma_construct_mem_to_stream_desc(
							&m2s_desc_contrast[i],  // current descriptor pointer
							&m2s_desc_contrast[i+1], // next descriptor pointer
							(alt_u32*)&input_image[(mtl+i)*width+ntl],  // read buffer location
							(alt_u16)P,  // length of the buffer
							0, // reads are not from a fixed location
							0, // start of packet is disabled for the Avalon-ST interfaces
							0, // end of packet is disabled for the Avalon-ST interfaces,
							0);  // there is only one channel

	for (alt_u32 i = 0; i < Q; i++)
		alt_avalon_sgdma_construct_stream_to_mem_desc(
								&s2m_desc_contrast[i],  // current descriptor pointer
								&s2m_desc_contrast[i+1], // next descriptor pointer
								(alt_u32*)&output_image[(mtl+i)*width+ntl],  // write buffer location
								(alt_u16)P,  // length of the buffer
								0); // writes are not to a fixed location

	/**************************************************************
	* Register the ISRs that will get called when each (full)  *
	* transfer completes. When park bit is set, processed      *
	* descriptors are not invalidated (OWNED_BY_HW bit stays 1)*
	* meaning that the same descriptors can be used for new    *
	* transfers.                                               *
	************************************************************/
	alt_avalon_sgdma_register_callback(sgdma_m2s_contrast,
									&transmit_callback_function,
									(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_PARK_MSK),
									(void*)&rx_done);

	alt_avalon_sgdma_register_callback(sgdma_s2m_contrast,
									&receive_callback_function,
									(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK |
									 ALTERA_AVALON_SGDMA_CONTROL_PARK_MSK),
								   (void*)&tx_done);

	/**************************************************************/
	PERF_RESET(PERFORMANCE_COUNTER_BASE);
	PERF_START_MEASURING(PERFORMANCE_COUNTER_BASE);

	PERF_BEGIN(PERFORMANCE_COUNTER_BASE, 1);
	IOWR_8DIRECT(CONTRAST_ACC_BASE, CONTROL_ADDRESS, PROCESS);

#if DEBUG
	contrast_control_reg = IORD_8DIRECT(CONTRAST_ACC_BASE, CONTROL_ADDRESS );
	printf("contrast_control_reg = %x\n", contrast_control_reg);
#endif

	transmit_status = alt_avalon_sgdma_do_async_transfer(sgdma_m2s_contrast, &m2s_desc_contrast[0]);
	receive_status = alt_avalon_sgdma_do_async_transfer(sgdma_s2m_contrast, &s2m_desc_contrast[0]);

	while(tx_done < 1) {}
	tx_done = 0;

	while(rx_done < 1) {}
	rx_done = 0;

	alt_avalon_sgdma_stop(sgdma_m2s_contrast);
	alt_avalon_sgdma_stop(sgdma_s2m_contrast);
	PERF_END(PERFORMANCE_COUNTER_BASE, 1);

	free(m2s_desc_contrast_copy);
	free(s2m_desc_contrast_copy);

#if DEBUG
	for (i = 0; i < 256; i++)
		printf("cumhist[%d] = %d\n",i , cumhist[i]);


	for (i = 0; i < 256; i++)
		printf("hist[%d] = %d\n",i , hist[i]);
#endif

	fp = fopen("/mnt/host/dark512_output.bin", "wb");

	fwrite(&width, sizeof(width), 1, fp);
	fwrite(&height, sizeof(height), 1, fp);
	printf("Writing output image ...\n");
	fwrite(output_image, 1, width*height, fp);
	printf("Output image written!\n\n");
	fclose(fp);

	free(output_image);
	free(input_image);

	perf_print_formatted_report(PERFORMANCE_COUNTER_BASE,
								alt_get_cpu_freq(),
								1,
								"Jednostavna"
								);

	printf("Exiting...");
	return 0;
}
