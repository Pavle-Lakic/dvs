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

#define STATUS_ADDRESS  0x00
#define CONTROL_ADDRESS 0x01
#define NOP_LOW_ADDRESS 0x02
#define NOP_MIDDLE_ADDRESS 0x03
#define NOP_HIGH_ADDRESS 0x04


int main()
{
	alt_u32  nop = 0;

	// Positions of corner pixels of rectangle in the picture on which the contrast is going to be done
	alt_u32 mtl = 0, mbr = 511, ntl = 0, nbr = 511;

	//Width and height of input picture - initialization
	alt_u32  width = 0, height = 0;

	alt_u32 nop_low = 0;
	alt_u32 nop_middle = 0;
	alt_u32 nop_high = 0;

	/*
	alt_u16 tx_done = 0;
	alt_u16 rx_done = 0;

	alt_u32 i=0, j=0;

	// Positions of corner pixels of rectangle in the picture on which the contrast is going to be done
	alt_u32 mtl = 0, mbr = 511, ntl = 0, nbr = 511;

	// Sizes of rectangle sides - initialization
	alt_u32 P =0, Q = 0;

	//Histogram initialization
	alt_u32 hist[256]={0};

	//Width and height of input picture - initialization
	alt_u32  width = 0, height = 0;

	//Pointers to file, all pixels of input image and all pixels of output image
	alt_u8 *input_image;

	FILE* fp;

	// Instead of bright64.bin available binary files are:
	  //bright512.bin, dark64.bin, dark512.bin, low_contrast64.bin, low_contrast512.bin
	fp = fopen("/mnt/host/bright512.bin", "rb");

	// First 4 bytes represents the width of a picture
	fread(&width, 4, 1, fp);

	// Second 4 bytes represents the height of a picture
	fread(&height, 4, 1, fp);

	// Allocating memory for input image
	input_image = (unsigned char*) malloc(width*height);

	// Coping image pixels to input_image array
	fread(input_image, 1, width*height, fp);
	printf("Input image loaded!\n");
	fclose(fp);

	int return_code = 0;

	//Sizes of rectangle sides
	P = mbr - mtl + 1;
	Q = nbr - ntl + 1;

	alt_sgdma_dev *sgdma_m2s = alt_avalon_sgdma_open("/dev/sgdma_m2s");
	alt_sgdma_dev *sgdma_s2m = alt_avalon_sgdma_open("/dev/sgdma_s2m");

	if (sgdma_m2s == NULL)
	{
		printf("Could not open the transmit SG-DMA for histogram\n");
		return 1;
	}
	if (sgdma_s2m == NULL)
	{
		printf("Could not open the receive SG-DMA for histogram\n");
		return 1;
	}

	alt_sgdma_descriptor *m2s_desc, *s2m_desc;
	void *temp_ptr;

	temp_ptr = malloc((Q + 2) * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL)
	{
		printf("\nFailed to allocate memory for the transmit descriptors\n");
		return 1;
	}

	while ((((alt_u32)temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0)
	{
		temp_ptr++;  // slide the pointer until 32 byte boundary is found
	}

	m2s_desc = (alt_sgdma_descriptor *)temp_ptr;
	m2s_desc[Q].control = 0;

	temp_ptr = malloc((1 + 2) * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL)
	{
		printf("\nFailed to allocate memory for the receive descriptors\n");
		return 1;
	}

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
							(alt_u16)256*sizeof(alt_u32),  // length of the buffer
							0); // writes are not to a fixed location
*/

	printf("Enter x position of top left pixel:\n");
	scanf("%lu", &mtl);

	printf("Enter y position of top left pixel:\n");
	scanf("%lu", &ntl);

	printf("Enter x position of bottom right pixel:\n");
	scanf("%lu", &mbr);

	printf("Enter y position of bottom right pixel:\n");
	scanf("%lu", &nbr);

	//Ubaciti proveru za unos brojeva

	width = mbr - mtl + 1;
	height = nbr - ntl + 1;

	nop = width * height;
	printf("Number of pixels %i\n", nop);

	nop_low = nop & 0x000000ff;
	nop_middle = (nop & 0x0000ff00) >> 8;
	nop_high = (nop & 0x00070000) >> 16;
/*
	printf("nop_low %i\n", nop_low);
	printf("nop_middle %i\n", nop_middle);
	printf("nop_high = %i\n", nop_high);
*/
	IOWR_8DIRECT(ACC_HIST_BASE, CONTROL_ADDRESS, 0xef);

	alt_u32 counter=0;

	alt_u32 control_reg = IORD_8DIRECT(ACC_HIST_BASE, CONTROL_ADDRESS );

	printf("control_reg %x\n", control_reg);

	IOWR_8DIRECT(ACC_HIST_BASE, NOP_LOW_ADDRESS, nop_low);

	nop_low = IORD_8DIRECT(ACC_HIST_BASE, NOP_LOW_ADDRESS );
/*
	while (counter < 100000) {counter++;}

	counter = 0;
*/
	printf("nop_low %i\n", nop_low);

	IOWR_8DIRECT(ACC_HIST_BASE, NOP_MIDDLE_ADDRESS, nop_middle);

	nop_middle = IORD_8DIRECT(ACC_HIST_BASE, NOP_MIDDLE_ADDRESS );

	printf("nop_middle %i\n", nop_middle);

	IOWR_8DIRECT(ACC_HIST_BASE, NOP_HIGH_ADDRESS, nop_high);

	nop_high = IORD_8DIRECT(ACC_HIST_BASE, NOP_HIGH_ADDRESS );

	printf("nop_high = %i\n", nop_high);

	alt_u32 status_reg = IORD_8DIRECT(ACC_HIST_BASE, STATUS_ADDRESS);

	printf("status_reg = %x\n", status_reg);
/*
	alt_u32 transmit_status = alt_avalon_sgdma_do_sync_transfer(sgdma_m2s, &m2s_desc[0]);

	while(tx_done < 1)
	{
		if(transmit_status & ALTERA_AVALON_SGDMA_STATUS_CHAIN_COMPLETED_MSK)
		{
			tx_done = 1;
			printf("The transmit SGDMA has completed!\n");
		}
	}
	printf("Start receive!\n");

	alt_u32 receive_status = alt_avalon_sgdma_do_sync_transfer(sgdma_s2m, &s2m_desc[0]);


	while(rx_done < 1)
	{
		if(receive_status & ALTERA_AVALON_SGDMA_STATUS_CHAIN_COMPLETED_MSK)
		{
			rx_done = 1;
			printf("The receive SGDMA has completed!\n");
		}
	}

	tx_done = 0;
	rx_done = 0;*/
	return 0;
}
