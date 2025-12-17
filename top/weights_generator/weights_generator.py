import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import os

# -------------------------------------------------------------------------
# 1. DEFINE THE MODEL ARCHITECTURE
# -------------------------------------------------------------------------
class LeNet5(nn.Module):
    def __init__(self):
        super(LeNet5, self).__init__()
        # C1: 1 input, 6 output, 5x5 kernel
        self.conv1 = nn.Conv2d(1, 6, kernel_size=5, stride=1, padding=0)
        self.relu1 = nn.ReLU()
        self.pool1 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        # C2: 6 input, 16 output, 5x5 kernel
        self.conv2 = nn.Conv2d(6, 16, kernel_size=5, stride=1, padding=0)
        self.relu2 = nn.ReLU()
        self.pool2 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        # FC Layers
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.relu3 = nn.ReLU()
        self.fc2 = nn.Linear(120, 84)
        self.relu4 = nn.ReLU()
        self.fc3 = nn.Linear(84, 10)

    def forward(self, x):
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        x = x.view(-1, 16 * 5 * 5)
        x = self.relu3(self.fc1(x))
        x = self.relu4(self.fc2(x))
        x = self.fc3(x)
        return x

# -------------------------------------------------------------------------
# 2. HELPER: FLOAT TO HEX CONVERTER (8-bit Signed)
# -------------------------------------------------------------------------
def to_hex(val):
    val = max(-128, min(127, int(val)))
    if val < 0:
        val = (1 << 8) + valx``
    return f"{val:02x}"

# -------------------------------------------------------------------------
# 3. TRAINING FUNCTION
# -------------------------------------------------------------------------
def train_model(model):
    print("\n--- 1. Preparing Data & Training (Approx 30s) ---")
    transform = transforms.Compose([
        transforms.Resize((32, 32)),
        transforms.ToTensor(),
        # DELETE or COMMENT OUT the Normalize line below:
        # transforms.Normalize((0.1307,), (0.3081,)) 
    ])
    
    # Download MNIST
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)
    
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    
    model.train()
    print("Training for 1 epoch...")
    
    # Train for just 1 epoch (sufficient for hardware verification)
    for batch_idx, (data, target) in enumerate(train_loader):
        optimizer.zero_grad()
        output = model(data)
        loss = criterion(output, target)
        loss.backward()
        optimizer.step()
        
        if batch_idx % 100 == 0:
            print(f"Batch {batch_idx}/{len(train_loader)} | Loss: {loss.item():.4f}")

    print("Training complete!")

# -------------------------------------------------------------------------
# 4. WEIGHT EXTRACTION
# -------------------------------------------------------------------------
def extract_weights(model):
    print("\n--- 2. Extracting Weights to Hex ---")
    os.makedirs("c1_weights", exist_ok=True)
    os.makedirs("c2_weights", exist_ok=True)

    # Calculate global scale factor
    max_val_c1 = torch.max(torch.abs(model.conv1.weight.data))
    max_val_c2 = torch.max(torch.abs(model.conv2.weight.data))
    global_max = max(max_val_c1, max_val_c2)
    scale_factor = 127.0 / float(global_max)
    
    print(f"Global Max Weight: {global_max:.4f}")
    print(f"Quantization Scale Factor: {scale_factor:.4f}")

    # --- C1 Weights ---
    c1_weights = model.conv1.weight.data
    for i in range(6):
        filename = f"c1_weights/weights_c1_{i}.hex"
        with open(filename, "w") as f:
            kernel = c1_weights[i, 0, :, :] 
            flat_kernel = kernel.flatten()
            for val in flat_kernel:
                quantized = val * scale_factor
                f.write(to_hex(quantized) + "\n")
        print(f"Saved {filename}")

    # --- C2 Weights ---
    c2_weights = model.conv2.weight.data
    for i in range(16):
        filename = f"c2_weights/weights_c2_{i}.hex"
        with open(filename, "w") as f:
            for input_ch in range(6):
                kernel = c2_weights[i, input_ch, :, :] 
                flat_kernel = kernel.flatten()
                for val in flat_kernel:
                    quantized = val * scale_factor
                    f.write(to_hex(quantized) + "\n")
        print(f"Saved {filename}")

def main():
    model = LeNet5()
    train_model(model)     # Train from scratch
    extract_weights(model) # Extract hex files

if __name__ == "__main__":
    main()