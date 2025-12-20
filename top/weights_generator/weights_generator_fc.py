import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import os
import math

# --- CONFIGURATION ---
EPOCHS = 5  
BATCH_SIZE = 64

class LeNet5(nn.Module):
    def __init__(self):
        super(LeNet5, self).__init__()
        # bias=False matches your FPGA hardware exactly
        self.conv1 = nn.Conv2d(1, 6, kernel_size=5, stride=1, padding=0, bias=False)
        self.relu1 = nn.ReLU()
        self.pool1 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv2 = nn.Conv2d(6, 16, kernel_size=5, stride=1, padding=0, bias=False)
        self.relu2 = nn.ReLU()
        self.pool2 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.fc1 = nn.Linear(16 * 5 * 5, 120, bias=False)
        self.relu3 = nn.ReLU()
        self.fc2 = nn.Linear(120, 84, bias=False)
        self.relu4 = nn.ReLU()
        self.fc3 = nn.Linear(84, 10, bias=False)

    def forward(self, x):
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        # PyTorch flattens as (Channel, Row, Col) -> Matches your FPGA S4 order!
        x = x.view(-1, 16 * 5 * 5)
        x = self.relu3(self.fc1(x))
        x = self.relu4(self.fc2(x))
        x = self.fc3(x)
        return x

def to_hex(val):
    # Clamp to ensure it fits in signed 8-bit
    val = max(-128, min(127, int(val)))
    if val < 0: val = (1 << 8) + val
    return f"{val:02x}"

def train_and_export():
    print(f"\n--- 1. Training LeNet-5 (No Bias) for {EPOCHS} Epochs ---")
    
    transform = transforms.Compose([transforms.Resize((32, 32)), transforms.ToTensor()])
    train_data = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    test_data = datasets.MNIST(root='./data', train=False, download=True, transform=transform)
    
    train_loader = DataLoader(train_data, batch_size=BATCH_SIZE, shuffle=True)
    test_loader = DataLoader(test_data, batch_size=1000, shuffle=False)
    
    model = LeNet5()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()
    
    # --- TRAINING LOOP ---
    for epoch in range(EPOCHS):
        model.train()
        for batch_idx, (data, target) in enumerate(train_loader):
            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()
            
        # Quick accuracy check
        correct = 0
        total = 0
        with torch.no_grad():
            for data, target in test_loader:
                outputs = model(data)
                _, predicted = torch.max(outputs.data, 1)
                total += target.size(0)
                correct += (predicted == target).sum().item()
        
        print(f"Epoch {epoch+1}/{EPOCHS} | Test Accuracy: {100 * correct / total:.2f}%")

    if (correct/total) < 0.90:
        print("\nWARNING: Accuracy is low. The generated weights might fail on '7'.")

    # --- WEIGHT EXTRACTION ---
    print("\n--- 2. Extracting Weights & Calculating Shifts ---")
    os.makedirs("c1_weights", exist_ok=True)
    os.makedirs("c2_weights", exist_ok=True)
    os.makedirs("fc_weights", exist_ok=True)

    # 1. Determine Global Scaling Factor for Weights
    # We find the largest weight in the entire network to maximize dynamic range
    max_val = 0
    for param in model.parameters():
        local_max = torch.max(torch.abs(param.data))
        if local_max > max_val: max_val = local_max
    
    # Scale so the largest weight fits in -127 to +127
    scale_factor = 127.0 / float(max_val) if max_val > 0 else 1.0
    print(f"Max Weight: {max_val:.4f} -> Scale Factor: {scale_factor:.4f}")

    # 2. Export Helper Function
    def export_layer(data, filename):
        with open(filename, "w") as f:
            for val in data.flatten():
                # Apply scaling before writing to Hex
                f.write(to_hex(val * scale_factor) + "\n")

    # Export C1
    for i in range(6):
        export_layer(model.conv1.weight.data[i, 0], f"c1_weights/weights_c1_{i}.hex")
    
    # Export C2 (Banked)
    for i in range(16):
        with open(f"c2_weights/weights_c2_{i}.hex", "w") as f:
            for ch in range(6):
                kernel = model.conv2.weight.data[i, ch].flatten()
                for val in kernel:
                    f.write(to_hex(val * scale_factor) + "\n")

    # Export FC Layers
    export_layer(model.fc1.weight.data, "fc_weights/c5_weights_flattened.hex")
    export_layer(model.fc2.weight.data, "fc_weights/f6_weights_flattened.hex")
    export_layer(model.fc3.weight.data, "fc_weights/out_weights_flattened.hex")

    # --- CALCULATE IDEAL SHIFT (THE FIX) ---
    # Logic: 
    # HW_Mult = (SW_Input * 127) * (SW_Weight * Scale_Factor)
    # HW_Mult = (SW_Input * SW_Weight) * (127 * Scale_Factor)
    # 
    # To get back to the 8-bit range (SW_Result * 127), we need:
    # HW_Output = HW_Mult >> SHIFT
    # 
    # Ideally: HW_Output approx (SW_Result * 127)
    # So: (SW_Result * 127) = [(SW_Result) * (127 * Scale_Factor)] / 2^SHIFT
    # 
    # Canceling terms: 
    # 1 = Scale_Factor / 2^SHIFT
    # 2^SHIFT = Scale_Factor
    # SHIFT = log2(Scale_Factor)

    ideal_shift = int(math.log2(scale_factor))
    
    # Safety clamp: Shift shouldn't be negative
    if ideal_shift < 0: ideal_shift = 0

    print("\n" + "="*40)
    print(f"RECOMMENDED FPGA SETTINGS")
    print("="*40)
    print(f"Update 'fc_streaming' .SHIFT parameters in fpga_top_layer1.sv:")
    print(f"   .SHIFT({ideal_shift})")
    print("="*40)

if __name__ == "__main__":
    train_and_export()