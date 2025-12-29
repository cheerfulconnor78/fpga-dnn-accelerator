import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import os

class LeNet5(nn.Module):
    def __init__(self):
        super(LeNet5, self).__init__()
        # CRITICAL CHANGE: bias=False for all layers to match FPGA
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
        self.fc3 = nn.Linear(84, 10, bias=False) # No ReLU, No Bias

    def forward(self, x):
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        x = x.view(-1, 16 * 5 * 5)
        x = self.relu3(self.fc1(x))
        x = self.relu4(self.fc2(x))
        x = self.fc3(x)
        return x

def to_hex(val):
    val = max(-128, min(127, int(val)))
    if val < 0: val = (1 << 8) + val
    return f"{val:02x}"

def train_model(model):
    print("\n--- 1. Training (No Biases) ---")
    # Normalize to -1.0 to 1.0 to match signed 8-bit inputs
    transform = transforms.Compose([
        transforms.Resize((32, 32)),
        transforms.ToTensor(),
        transforms.Normalize((0.5,), (0.5,)) 
    ])
    
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)
    
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    
    model.train()
    for batch_idx, (data, target) in enumerate(train_loader):
        optimizer.zero_grad()
        output = model(data)
        loss = criterion(output, target)
        loss.backward()
        optimizer.step()
        if batch_idx % 200 == 0: print(f"Batch {batch_idx} Loss: {loss.item():.4f}")

def extract_weights(model):
    print("\n--- 2. Extracting Weights ---")
    os.makedirs("c1_weights", exist_ok=True)
    os.makedirs("c2_weights", exist_ok=True)
    os.makedirs("fc_weights", exist_ok=True)

    global_max = 0
    for param in model.parameters():
        local_max = torch.max(torch.abs(param.data))
        if local_max > global_max: global_max = local_max
    
    scale_factor = 127.0 / float(global_max)
    print(f"Scale Factor: {scale_factor:.4f}")

    # Extract C1
    c1_weights = model.conv1.weight.data
    for i in range(6):
        with open(f"c1_weights/weights_c1_{i}.hex", "w") as f:
            for val in c1_weights[i, 0].flatten():
                f.write(to_hex(val * scale_factor) + "\n")

    # Extract C2
    c2_weights = model.conv2.weight.data
    for i in range(16):
        with open(f"c2_weights/weights_c2_{i}.hex", "w") as f:
            for ch in range(6):
                for val in c2_weights[i, ch].flatten():
                    f.write(to_hex(val * scale_factor) + "\n")

    # Extract FCs
    for layer, name in [(model.fc1, "c5"), (model.fc2, "f6"), (model.fc3, "out")]:
        with open(f"fc_weights/{name}_weights_flattened.hex", "w") as f:
            for val in layer.weight.data.flatten():
                f.write(to_hex(val * scale_factor) + "\n")

def main():
    model = LeNet5()
    train_model(model)     
    extract_weights(model) 

if __name__ == "__main__":
    main()