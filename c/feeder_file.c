#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <string.h>

#define HW_REGS_BASE (0xFF200000)
#define HW_REGS_SPAN (0x00200000)
#define RAM_OFFSET   (0x00040000)
#define CTRL_OFFSET  (0x00050000)

void print_ascii(uint8_t grid[32][32], const char* label) {
    printf("\n--- %s ---\n", label);
    for (int r = 0; r < 32; r++) {
        printf("%02d: ", r);
        for (int c = 0; c < 32; c++) {
            printf("%c ", (grid[r][c] > 0) ? '#' : '.');
        }
        printf("\n");
    }
}

int main() {
    int fd;
    FILE *hex_fp;
    void *virtual_base;
    volatile uint32_t *ram_ptr;
    volatile uint32_t *ctrl_ptr;
    char line_buffer[16];

    // 1. MAP MEMORY
    if((fd = open("/dev/mem", (O_RDWR | O_SYNC))) == -1) return 1;
    virtual_base = mmap(NULL, HW_REGS_SPAN, (PROT_READ | PROT_WRITE), MAP_SHARED, fd, HW_REGS_BASE);
    if(virtual_base == MAP_FAILED) return 1;
    ram_ptr  = (volatile uint32_t *)((char *)virtual_base + RAM_OFFSET);
    ctrl_ptr = (volatile uint32_t *)((char *)virtual_base + CTRL_OFFSET);

    // 2. LOAD RAW IMAGE
    hex_fp = fopen("image.hex", "r");
    if (!hex_fp) { printf("ERR: No image.hex\n"); return 1; }

    uint8_t raw_data[1024];
    memset(raw_data, 0, 1024);
    int count = 0;
    while(fgets(line_buffer, sizeof(line_buffer), hex_fp) && count < 1024) {
        int val = (int)strtol(line_buffer, NULL, 16);
        raw_data[count] = (val > 10) ? 127 : 0; // Hard Threshold
        count++;
    }
    fclose(hex_fp);

    // 3. COPY TO 2D GRID (Assuming 32x32 based on your previous run)
    uint8_t original[32][32];
    memset(original, 0, sizeof(original));
    for(int i=0; i<count; i++) original[i/32][i%32] = raw_data[i];

    print_ascii(original, "ORIGINAL (Input)");

    // 4. FIND BOUNDING BOX
    int min_r = 32, max_r = -1, min_c = 32, max_c = -1;
    for (int r = 0; r < 32; r++) {
        for (int c = 0; c < 32; c++) {
            if (original[r][c] > 0) {
                if (r < min_r) min_r = r;
                if (r > max_r) max_r = r;
                if (c < min_c) min_c = c;
                if (c > max_c) max_c = c;
            }
        }
    }

    if (max_r == -1) { printf("ERR: Image is blank!\n"); return 1; }

    // 5. CENTER IT
    uint8_t centered[32][32];
    memset(centered, 0, sizeof(centered));

    int h = max_r - min_r + 1;
    int w = max_c - min_c + 1;
    int start_r = (32 - h) / 2;
    int start_c = (32 - w) / 2;

    for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
            centered[start_r + r][start_c + c] = original[min_r + r][min_c + c];
        }
    }

    print_ascii(centered, "CENTERED (Will Send to FPGA)");
    printf("Does the CENTERED image look correct? [Press Enter to Trigger]");
    getchar();

    // 6. WRITE TO FPGA
    // Clear RAM
    for(int i=0; i<256; i++) ram_ptr[i] = 0;

    int word_idx = 0;
    for(int r=0; r<32; r++) {
        for(int c=0; c<32; c+=4) {
            uint32_t pack = 0;
            pack |= (uint32_t)centered[r][c+0] << 0;
            pack |= (uint32_t)centered[r][c+1] << 8;
            pack |= (uint32_t)centered[r][c+2] << 16;
            pack |= (uint32_t)centered[r][c+3] << 24;
            ram_ptr[word_idx++] = pack;
        }
    }

    // 7. TRIGGER
    *ctrl_ptr = 1;
    usleep(100);
    *ctrl_ptr = 0;
    printf("Done. Check LEDs.\n");

    return 0;
}