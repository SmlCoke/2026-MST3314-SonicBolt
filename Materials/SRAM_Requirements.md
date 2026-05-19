# SRAM Requirements

SRAM 需求如下：

| 所属模块 | 功能 | Word Entry | Word Width | 
| --- | --- | --- | --- |
| Conv | weight | 32 | 112bit |
| Conv/DWConv/PWConv | bias | 32 | 64bit |
| Conv | feature map | 32 | 80bit |
| DWConv | weight | 32 | 96bit |
| PWConv | weight | 32 | 128bit |
| FC     | weight | 80 | 64bit |
| Sigmoid | weight | 256 | 32bit |
