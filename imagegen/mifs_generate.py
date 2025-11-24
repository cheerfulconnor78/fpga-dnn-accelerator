import random

# --- HARDWARE CONSTANTS ---
MAPSIZE = 32
WEIGHTS = [
    [ 0,  0, -1,  0,  0],
    [ 0, -1, -2, -1,  0],
    [-1, -2, 16, -2, -1],
    [ 0, -1, -2, -1,  0],
    [ 0,  0, -1,  0,  0]
]

# Replace generate_image with this:
def generate_image(size):
    # Gradient pattern: 0, 1, 2, ... 255, 0, 1...
    return [(i % 100) for i in range(size * size)]

def apply_layer1(image):
    # 1. CONVOLUTION (Valid Padding)
    conv_out = []
    out_dim_conv = MAPSIZE - 4 # 28
    
    for r in range(out_dim_conv):
        for c in range(out_dim_conv):
            # Window 5x5
            acc = 0
            for wr in range(5):
                for wc in range(5):
                    # Pixel index in 32x32 image
                    # Row = r + wr, Col = c + wc
                    idx = (r + wr) * MAPSIZE + (c + wc)
                    px = image[idx]
                    w = WEIGHTS[wr][wc]
                    acc += px * w
            conv_out.append(acc)

    # 2. RELU + SATURATION + SCALING
    relu_out = []
    for val in conv_out:
        # Scale (Shift Right by 0 - Change if your hardware OUTPUT_SHIFT != 0)
        val = val >> 0 
        
        # ReLU & Saturate
        if val < 0: val = 0
        elif val > 127: val = 127
        
        relu_out.append(val)

    # 3. MAXPOOL (2x2, Stride 2)
    pool_out = []
    out_dim_pool = out_dim_conv // 2 # 14
    
    # Reshape relu_out to 2D for easier indexing
    relu_2d = [relu_out[i:i+28] for i in range(0, len(relu_out), 28)]

    for r in range(out_dim_pool):
        for c in range(out_dim_pool):
            # 2x2 Window coordinates
            r2 = r * 2
            c2 = c * 2
            
            p0 = relu_2d[r2][c2]
            p1 = relu_2d[r2][c2+1]
            p2 = relu_2d[r2+1][c2]
            p3 = relu_2d[r2+1][c2+1]
            
            # Max
            mx = max(p0, p1, p2, p3)
            pool_out.append(mx)

    return pool_out

def write_mif(filename, depth, width, data):
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {depth};\nWIDTH = {width};\n")
        f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for i, val in enumerate(data):
            f.write(f"{i:X} : {val:02X};\n")
        f.write("END;\n")
    print(f"Generated {filename} with {len(data)} items.")

# --- MAIN EXECUTION ---
input_pixels = generate_image(MAPSIZE)
golden_pixels = apply_layer1(input_pixels)

write_mif("image.mif", 1024, 8, input_pixels)
write_mif("golden_layer1.mif", 196, 8, golden_pixels)
