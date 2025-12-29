import os

# --- CONFIGURATION ---
MAPSIZE = 32
OUTPUT_SHIFT = 8  # Match your Verilog localparam

# --- HELPER FUNCTIONS ---
def load_hex_weights(filename):
    """Loads a .hex file with signed 8-bit values."""
    if not os.path.exists(filename):
        print(f"Error: Missing {filename}")
        # Return zeros if missing so script doesn't crash immediately
        return [0] * 25 
    
    weights = []
    with open(filename, 'r') as f:
        for line in f:
            val_hex = line.strip()
            if not val_hex: continue
            val = int(val_hex, 16)
            # Handle 2's complement
            if val > 127: val -= 256
            weights.append(val)
    return weights

def write_mif(filename, data):
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {len(data)};\nWIDTH = 8;\n")
        f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for i, val in enumerate(data):
            # Mask to 8-bit hex for display
            val_8bit = val & 0xFF 
            f.write(f"{i:X} : {val_8bit:02X};\n")
        f.write("END;\n")
    print(f"Generated {filename} with {len(data)} items.")

def relu_scale_pool_layer(conv_output, out_dim_conv):
    """Applies ReLU, Shift, Saturation, and 2x2 MaxPool."""
    pool_out = []
    out_dim_pool = out_dim_conv // 2
    
    # Process 2x2 blocks
    for r in range(out_dim_pool):
        for c in range(out_dim_pool):
            vals = []
            for pr in range(2):
                for pc in range(2):
                    # Index in the larger conv map
                    idx = (r*2 + pr) * out_dim_conv + (c*2 + pc)
                    val = conv_output[idx]
                    
                    # 1. Scale (Shift)
                    val = val >> OUTPUT_SHIFT
                    
                    # 2. ReLU
                    if val < 0: val = 0
                    
                    # 3. Saturate (Clip to 127)
                    if val > 127: val = 127
                    
                    vals.append(val)
            # 4. MaxPool
            pool_out.append(max(vals))
    return pool_out

# --- MAIN SIMULATION ---
def run_simulation():
    print("--- Starting Layer 1 + Layer 2 Simulation ---")

    # 1. GENERATE INPUT IMAGE (Gradient 0..99)
    # -------------------------------------------
    input_image = [(i % 100) for i in range(1024)]
    write_mif("image.mif", input_image)

    # 2. SIMULATE LAYER 1 (6 Parallel Channels)
    # -------------------------------------------
    l1_feature_maps = [] # Will store 6 maps of 14x14 (196 pixels each)
    
    for ch in range(6):
        # Load weights (25 items)
        w_path = f"c1_weights/weights_c1_{ch}.hex"
        weights = load_hex_weights(w_path)
        w_5x5 = [weights[i:i+5] for i in range(0, 25, 5)]
        
        # Convolution (32x32 -> 28x28)
        conv_out = []
        for r in range(28):
            for c in range(28):
                acc = 0
                for wr in range(5):
                    for wc in range(5):
                        px = input_image[(r+wr)*32 + (c+wc)]
                        w = w_5x5[wr][wc]
                        acc += px * w
                conv_out.append(acc)
        
        # Pipeline: ReLU -> Scale -> Pool (Output 14x14)
        pool_result = relu_scale_pool_layer(conv_out, 28)
        l1_feature_maps.append(pool_result)
        
    print(f"Layer 1 Done. Generated {len(l1_feature_maps)} maps of size {len(l1_feature_maps[0])}.")

    # 3. SIMULATE LAYER 2 (Channel 0 Only)
    # -------------------------------------------
    # Channel 0 needs to read 'weights_c2_0.hex' which has 150 lines
    print("Simulating Layer 2 (Channel 0)...")
    
    w_c2_0 = load_hex_weights("c2_weights/weights_c2_0.hex")
    if len(w_c2_0) < 150:
        print("ERROR: weights_c2_0.hex is too short! Run generate_lenet_weights.py again.")
        return

    # Split 150 weights into 6 kernels of 5x5
    kernels_linear = [w_c2_0[i:i+25] for i in range(0, 150, 25)]
    kernels_2d = [[k[j:j+5] for j in range(0, 25, 5)] for k in kernels_linear]
    
    # Accumulate Convolution (Input 14x14 -> Output 10x10)
    l2_conv_acc = [0] * (10 * 10)
    
    # For each input channel (0 to 5)
    for ch_idx in range(6):
        input_map = l1_feature_maps[ch_idx] # 14x14
        kernel = kernels_2d[ch_idx]         # 5x5
        
        for r in range(10):
            for c in range(10):
                acc = 0
                for wr in range(5):
                    for wc in range(5):
                        px = input_map[(r+wr)*14 + (c+wc)]
                        w = kernel[wr][wc]
                        acc += px * w
                
                # Add to the global accumulator for this pixel
                l2_conv_acc[r*10 + c] += acc

    # Pipeline: ReLU -> Scale -> Pool (Output 5x5)
    l2_final_output = relu_scale_pool_layer(l2_conv_acc, 10)
    
    # 4. SAVE GOLDEN FILE
    # -------------------------------------------
    write_mif("golden_layer2.mif", l2_final_output)
    print("Success! golden_layer2.mif generated.")

if __name__ == "__main__":
    run_simulation()
