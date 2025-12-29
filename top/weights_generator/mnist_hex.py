import torch
from torchvision import datasets, transforms
import os

# --- CONFIGURATION ---
TARGET_DIGIT = 8   # Change this to test different digits
FILENAME = "image.hex" # Changed extension to .hex for readmemh compatibility
MAPSIZE = 32       

def write_hex(filename, data):
    """
    Writes raw hex values to a file, one per line.
    This format is completely compatible with Verilog's $readmemh().
    """
    with open(filename, 'w') as f:
        for val in data:
            # Mask to 8-bit to ensure clean hex (e.g., 255 -> FF)
            val_8bit = val & 0xFF 
            f.write(f"{val_8bit:02X}\n") # Write hex value followed by newline
    print(f"Success! Generated {filename} with a handwritten '{TARGET_DIGIT}'.")

def main():
    print(f"Searching MNIST for a digit '{TARGET_DIGIT}'...")
    
    # Standard load (0.0 to 1.0)
    transform = transforms.Compose([
        transforms.Resize((MAPSIZE, MAPSIZE)),
        transforms.ToTensor()
    ])
    
    # Download dataset if needed
    try:
        dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)
    except Exception as e:
        print(f"Error downloading dataset: {e}")
        return
    
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
        # --- SCALING FIX ---
        # Map 0.0 -> 0 (Black)
        # Map 1.0 -> 127 (Max Positive Signed 8-bit)
        # This prevents "negative" background noise (-128) which breaks the FPGA logic.
        val = int(p * 127)
        
        # Clamp just in case to stay within safe bounds
        val = max(0, min(127, val))
        pixels_int.append(val)
        
        # ASCII Visualization
        if i % 32 == 0: print() 
        char_idx = int(p * 9)
        char = " .:-=+*#%@"[char_idx] 
        print(f"{char} ", end="")
        
    print("\n-----------------------------------")
    
    # Use the new write_hex function
    write_hex(FILENAME, pixels_int)

if __name__ == "__main__":
    main()
