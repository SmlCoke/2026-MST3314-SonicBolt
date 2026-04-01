# SRAM Requirements

SRAM 需求如下：

| 所属模块 | 功能 | Word Entry | Word Width | 
| --- | --- | --- | --- |
| Conv | weight | 8 | 224bit |
| Conv/DWConv/PWConv | bias | 8 | 64bit |
| Conv | feature map | 30 | 80bit |
| DWConv | weight | 8 | 96bit |
| PWConv | weight | 8 | 128bit |