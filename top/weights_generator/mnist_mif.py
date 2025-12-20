import torch
from torchvision import datasets, transforms
import os

# --- CONFIGURATION ---
TARGET_DIGIT = 7   # Change this to test different digits
FILENAME = "image.mif"
MAPSIZE = 32       

def write_mif(filename, data):
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {len(data)};\nWIDTH = 8;\n")
        f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for i, val in enumerate(data):
            # Mask to 8-bit (handles 2's complement if you ever needed negatives)
            val_8bit = val & 0xFF 
            f.write(f"{i:X} : {val_8bit:02X};\n")
        f.write("END;\n")
    print(f"Success! Generated {filename} with a handwritten '{TARGET_DIGIT}'.")

def main():
    print(f"Searching MNIST for a digit '{TARGET_DIGIT}'...")
    
    # Standard load (0.0 to 1.0)
    transform = transforms.Compose([
        transforms.Resize((MAPSIZE, MAPSIZE)),
        transforms.ToTensor()
    ])
    
    dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)
    
    found_img = None
    for img, label in dataset:
        if label == TARGET_DIGIT:
            found_img = img
            break
            
    if found_img is None:
        print(f"Error: Could not find a {TARGET_DIGIT} in the dataset.")
        return

    pixels_float = found_img.flatten().tolist()
    pixels_int = []
    
    print("\n--- ASCII PREVIEW (Range 0 to 127) ---")
    for i, p in enumerate(pixels_float):
        # --- CRITICAL FIX ---
        # Map 0.0 -> 0 (Black)
        # Map 1.0 -> 127 (Max Positive Signed 8-bit)
        # This prevents "negative" background noise.
        val = int(p * 127)
        
        # Clamp just in case
        val = max(0, min(127, val))
        pixels_int.append(val)
        
        # Visualization
        if i % 32 == 0: print() 
        char_idx = int(p * 9)
        char = " .:-=+*#%@"[char_idx] 
        print(f"{char} ", end="")
        
    print("\n-----------------------------------")
    
    write_mif(FILENAME, pixels_int)

if __name__ == "__main__":
    main()