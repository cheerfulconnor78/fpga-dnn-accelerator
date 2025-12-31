#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>

#define HW_REGS_BASE (0xFF200000)
#define HW_REGS_SPAN (0x00200000)
#define RAM_OFFSET   (0x00040000)
#define TOTAL_PIXELS 1024
#define IMG_WIDTH    32

// Helper to convert pixel intensity (0-127) to a character
char pixel_to_ascii(uint32_t val) {
    if (val < 25)  return '.';  // Background
    if (val < 60)  return '+';  // Grey
    return '#';                 // Ink
}

int main() {
    int fd;
    FILE *hex_fp;
    void *virtual_base;
    volatile uint32_t *ram_ptr;
    char line_buffer[16];
    
    // 1. Open image.hex
    hex_fp = fopen("image.hex", "r");
    if (hex_fp == NULL) {
        printf("ERROR: Could not open image.hex in current folder.\n");
        return 1;
    }

    // 2. Open Memory Map
    if( ( fd = open( "/dev/mem", ( O_RDWR | O_SYNC ) ) ) == -1 ) {
        printf("ERROR: Could not open /dev/mem\n");
        return 1;
    }
    
    virtual_base = mmap( NULL, HW_REGS_SPAN, ( PROT_READ | PROT_WRITE ), MAP_SHARED, fd, HW_REGS_BASE );
    if( virtual_base == MAP_FAILED ) {
        printf("ERROR: mmap failed\n");
        close(fd);
        return 1;
    }
    
    ram_ptr = (volatile uint32_t *)( (char *)virtual_base + RAM_OFFSET );

    printf("Loading image.hex to FPGA (Scaled / 2)...\n\n");
    printf("--- IMAGE PREVIEW (32x32) ---\n");

    int words_written = 0;
    char row_buffer[IMG_WIDTH + 1]; 
    int row_idx = 0;

    for (int i = 0; i < TOTAL_PIXELS / 4; i++) {
        uint32_t packed_word = 0;
        uint32_t p[4] = {0, 0, 0, 0};

        // Read 4 pixels
        for (int k = 0; k < 4; k++) {
            if (fgets(line_buffer, sizeof(line_buffer), hex_fp)) {
                // Read original hex value (e.g., 255)
                uint32_t original_val = (uint32_t)strtol(line_buffer, NULL, 16);
                
                // CRITICAL FIX: Divide by 2 to fit into signed 8-bit positive range (0-127)
                p[k] = original_val / 2;
                
                // Pack into the word (Little Endian)
                packed_word |= ((p[k] & 0xFF) << (k * 8));

                // Add to ASCII row buffer
                row_buffer[row_idx++] = pixel_to_ascii(p[k]);
                
                if (row_idx == IMG_WIDTH) {
                    row_buffer[IMG_WIDTH] = '\0'; 
                    printf("%s\n", row_buffer);
                    row_idx = 0;
                }
            }
        }

        // Write the packed word to the FPGA RAM
        ram_ptr[i] = packed_word;
        words_written++;
    }

    printf("-----------------------------\n");
    printf("Done. Written %d packed words.\n", words_written);

    munmap( virtual_base, HW_REGS_SPAN );
    close( fd );
    fclose(hex_fp);
    return 0;
}