import torch.nn as nn
import torch.quantization


class MeinCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.quant = torch.quantization.QuantStub()

        self.conv1 = nn.Conv2d(in_channels=1, out_channels=8, kernel_size=3)
        self.relu1 = nn.ReLU()

        self.conv2 = nn.Conv2d(in_channels=8, out_channels=16, kernel_size=3)
        self.relu2 = nn.ReLU()

        self.pool = nn.MaxPool2d(kernel_size=2, stride=2)

        self.fc1 = nn.Linear(16 * 5 * 5, 64)
        self.relu3 = nn.ReLU()
        self.fc2 = nn.Linear(64, 10)

        self.dequant = torch.quantization.DeQuantStub()

    def forward(self, x):
        # x hat Shape: [batch, 1, 28, 28]
        x = self.quant(x)                          # float32 -> int8 (after convert)
        x = self.pool(self.relu1(self.conv1(x)))
        x = self.pool(self.relu2(self.conv2(x)))
        x = x.reshape(x.size(0), -1)
        x = self.relu3(self.fc1(x))
        x = self.fc2(x)
        x = self.dequant(x)                        # int8 -> float32
        return x

    def fuse_model(self):
        # Each ReLU must be a unique module instance for fusion to work.
        torch.quantization.fuse_modules(
            self,
            [['conv1', 'relu1'], ['conv2', 'relu2'], ['fc1', 'relu3']],
            inplace=True,
        )
