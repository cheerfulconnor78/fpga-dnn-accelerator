import torch
import torch.nn as nn
from torchvision import transforms
import os

# --- CONFIGURATION ---
# Ensure these match your FPGA settings
OUTPUT_SHIFT = 8 

# --- HELPER: Load Hex Weights ---
def load_hex_weights(filename):
    """Loads a flat .hex file into a list of integers"""
    if not os.path.exists(filename):
        print(f"Error: {filename} not found.")
        return []
    weights = []
    with open(filename, 'r') as f:
        for line in f:
            val_hex = line.strip()
            if not val_hex: continue
            val = int(val_hex, 16)
            if val > 127: val -= 256
            weights.append(val)
    return weights

# --- HELPER: Hardware-Accurate Matrix Multiply ---
def hardware_fc_layer(input_vec, weights_flat, num_outputs):
    """
    Simulates the FPGA FC layer:
    1. Dot Product
    2. ReLU (Zero out negatives)
    3. Shift (>> 8)
    """
    num_inputs = len(input_vec)
    output_vec = []
    
    # weights_flat is ordered: [Neuron0_In0...Neuron0_InN, Neuron1_In0...]
    
    for i in range(num_outputs):
        acc = 0
        # Slice weights for this neuron
        start_idx = i * num_inputs
        neuron_weights = weights_flat[start_idx : start_idx + num_inputs]
        
        # Dot Product
        for j in range(num_inputs):
            acc += input_vec[j] * neuron_weights[j]
            
        # Hardware Post-Processing
        # 1. ReLU logic in your FPGA is applied AFTER shift? 
        # Wait, your code: "if (accumulator > 0) data_out <= accumulator >>> 8"
        # This implies ReLU is done on the full accumulator.
        
        if acc > 0:
            res = acc >> OUTPUT_SHIFT
        else:
            res = 0
            
        # Saturate to 8-bit signed (just in case, though usually 0-127 for ReLU)
        if res > 127: res = 127
        
        output_vec.append(res)
        
    return output_vec

def write_mif(filename, data):
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {len(data)};\nWIDTH = 8;\n")
        f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for i, val in enumerate(data):
            val_8bit = val & 0xFF 
            f.write(f"{i:X} : {val_8bit:02X};\n")
        f.write("END;\n")
    print(f"Generated {filename} (Size: {len(data)})")

def main():
    print("--- Generating Golden Data for F6 ---")
    
    # 1. Generate Input Image (Same gradient as before)
    # This must match what your FPGA 'image.mif' contains
    input_image = [(i % 100) for i in range(1024)]
    
    # 2. Simulate Layer 1 & 2 (Quick approximation or load previous?)
    # Since we need exact bit-match, we must simulate the whole chain or 
    # assume you have a way to dump the S4 output. 
    # To be safe, let's load the weights and run the Full Forward Pass in Python
    # exactly as the FPGA does (Integer math only).
    
    # Load Weights
    w_c1 = [load_hex_weights(f"c1_weights/weights_c1_{i}.hex") for i in range(6)]
    w_c2 = [load_hex_weights(f"c2_weights/weights_c2_{i}.hex") for i in range(16)]
    w_c5 = load_hex_weights("fc_weights/c5_weights_flattened.hex")
    w_f6 = load_hex_weights("fc_weights/f6_weights_flattened.hex")
    
    if not w_c5 or not w_f6: return

    # --- SIMULATE L1 (Brief) ---
    l1_maps = []
    for ch in range(6):
        # ... (Convolution logic simplified for brevity - assumes you have this from before)
        # For simplicity, let's assume you ran the previous script and have 'golden_layer2.mif'
        # BUT 'golden_layer2.mif' is only 5x5 (one channel output?).
        pass
    
    # NOTE: To get a true Golden Vector for F6, you need to run the full simulation.
    # Since writing the full simulator here is long, can we rely on the previous scripts?
    # Or better: Can we just generate random inputs for C5 to test C5-F6 in isolation?
    # NO, because your FPGA runs from the very beginning (Image -> L1 -> L2 -> Bridge -> C5).
    
    # CRITICAL: We need the exact output of S4 to feed into C5 calculation.
    # I will provide a full simulation script in the next turn if you need it.
    # For now, ensure you have 'c5_weights_flattened.hex' and 'f6_weights_flattened.hex'.
    
    print("WARNING: To generate golden_f6.mif, we need to run the full L1->S4 pipeline first.")
    print("Please use the 'full_system_golden_gen.py' script provided next.")

if __name__ == "__main__":
    main()
