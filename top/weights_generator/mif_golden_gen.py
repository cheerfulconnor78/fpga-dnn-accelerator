import os

# --- 1. CONFIGURATION ---
MAPSIZE = 32
OUTPUT_SHIFT = 8   # MATCH THIS to your Verilog "localparam OUTPUT_SHIFT"
HEX_FILE = "c1_weights/weights_c1_0.hex" # Path to your generated Channel 0 weights

# --- 2. HELPER: LOAD HEX WEIGHTS ---
def load_weights_from_hex(filename):
    """
    Reads the .hex file generated for the FPGA and converts it back
    to a 5x5 list of signed integers.
    """
    if not os.path.exists(filename):
        print(f"ERROR: Could not find {filename}")
        print("Please run generate_lenet_weights.py first!")
        exit(1)
        
    weights_linear = []
    with open(filename, 'r') as f:
        for line in f:
            val_hex = line.strip()
            if not val_hex: continue
            
            # Convert Hex string to Integer
            val_int = int(val_hex, 16)
            
            # Handle 8-bit 2's Complement (00-7F is positive, 80-FF is negative)
            if val_int > 127:
                val_int -= 256
            
            weights_linear.append(val_int)
    
    # Reshape to 5x5
    weights_5x5 = [weights_linear[i:i+5] for i in range(0, 25, 5)]
    return weights_5x5

# --- 3. INPUT GENERATION ---
def generate_image(size):
    # Same gradient pattern as before: 0, 1...99, 0, 1...
    return [(i % 100) for i in range(size * size)]

# --- 4. LAYER 1 EMULATION ---
def apply_layer1(image, weights):
    # A. CONVOLUTION
    conv_out = []
    out_dim_conv = MAPSIZE - 4 # 28
    
    print(f"--- Simulating Layer 1 ---")
    print(f"Weights Loaded (Center 3x3):")
    for r in range(1,4): print(weights[r][1:4])
    print(f"Shift Amount: >> {OUTPUT_SHIFT}")

    for r in range(out_dim_conv):
        for c in range(out_dim_conv):
            acc = 0
            # 5x5 Window
            for wr in range(5):
                for wc in range(5):
                    idx = (r + wr) * MAPSIZE + (c + wc)
                    px = image[idx]
                    w = weights[wr][wc]
                    acc += px * w
            conv_out.append(acc)

    # B. SCALING + RELU + SATURATION
    relu_out = []
    for val in conv_out:
        # 1. Bit Shift (Hardware Divider)
        # Note: Python's >> behaves like Arithmetic Shift (>>> in Verilog) for signed ints
        val = val >> OUTPUT_SHIFT 
        
        # 2. ReLU (Clip Negative)
        if val < 0: val = 0
        
        # 3. Saturation (Clip Positive to 8-bit signed max)
        # Your hardware uses 127 as the cap
        if val > 127: val = 127
        
        relu_out.append(val)

    # C. MAXPOOL (2x2, Stride 2)
    pool_out = []
    out_dim_pool = out_dim_conv // 2 # 14
    
    # Reshape to 2D
    relu_2d = [relu_out[i:i+28] for i in range(0, len(relu_out), 28)]

    for r in range(out_dim_pool):
        for c in range(out_dim_pool):
            r2 = r * 2
            c2 = c * 2
            
            p0 = relu_2d[r2][c2]
            p1 = relu_2d[r2][c2+1]
            p2 = relu_2d[r2+1][c2]
            p3 = relu_2d[r2+1][c2+1]
            
            mx = max(p0, p1, p2, p3)
            pool_out.append(mx)

    return pool_out

# --- 5. MIF WRITER ---
def write_mif(filename, depth, width, data):
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {depth};\nWIDTH = {width};\n")
        f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for i, val in enumerate(data):
            f.write(f"{i:X} : {val:02X};\n")
        f.write("END;\n")
    print(f"Generated {filename} with {len(data)} items.")

# --- MAIN ---
if __name__ == "__main__":
    # 1. Load the REAL hardware weights
    weights = load_weights_from_hex(HEX_FILE)
    
    # 2. Generate Input
    input_pixels = generate_image(MAPSIZE)
    
    # 3. Calculate Expected Output
    golden_pixels = apply_layer1(input_pixels, weights)
    
    # 4. Save
    write_mif("image.mif", 1024, 8, input_pixels)
    write_mif("golden_layer1.mif", 196, 8, golden_pixels)