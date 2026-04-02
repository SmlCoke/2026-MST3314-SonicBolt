/*
    Copyright (c) 2026 SMIC
    Filename:      S018V3EBCDSP_X8Y4D128_PR.v
    IP code :      S018V3EBCDSP
    Version:       0.1.a
    CreateDate:    Mar 31, 2026

    Verilog Model for Single-PORT SRAM
    SMIC 0.18um V3EBCD

    Configuration: -instname S018V3EBCDSP_X8Y4D128_PR -rows 8 -bits 128 -mux 4 
    Redundancy: Off
    Bit-Write: Off
*/

/* DISCLAIMER                                                                      */
/*                                                                                 */  
/*   SMIC hereby provides the quality information to you but makes no claims,      */
/* promises or guarantees about the accuracy, completeness, or adequacy of the     */
/* information herein. The information contained herein is provided on an "AS IS"  */
/* basis without any warranty, and SMIC assumes no obligation to provide support   */
/* of any kind or otherwise maintain the information.                              */  
/*   SMIC disclaims any representation that the information does not infringe any  */
/* intellectual property rights or proprietary rights of any third parties. SMIC   */
/* makes no other warranty, whether express, implied or statutory as to any        */
/* matter whatsoever, including but not limited to the accuracy or sufficiency of  */
/* any information or the merchantability and fitness for a particular purpose.    */
/* Neither SMIC nor any of its representatives shall be liable for any cause of    */
/* action incurred to connect to this service.                                     */  
/*                                                                                 */
/* STATEMENT OF USE AND CONFIDENTIALITY                                            */  
/*                                                                                 */  
/*   The following/attached material contains confidential and proprietary         */  
/* information of SMIC. This material is based upon information which SMIC         */  
/* considers reliable, but SMIC neither represents nor warrants that such          */
/* information is accurate or complete, and it must not be relied upon as such.    */
/* This information was prepared for informational purposes and is for the use     */
/* by SMIC's customer only. SMIC reserves the right to make changes in the         */  
/* information at any time without notice.                                         */  
/*   No part of this information may be reproduced, transmitted, transcribed,      */  
/* stored in a retrieval system, or translated into any human or computer          */ 
/* language, in any form or by any means, electronic, mechanical, magnetic,        */  
/* optical, chemical, manual, or otherwise, without the prior written consent of   */
/* SMIC. Any unauthorized use or disclosure of this material is strictly           */  
/* prohibited and may be unlawful. By accepting this material, the receiving       */  
/* party shall be deemed to have acknowledged, accepted, and agreed to be bound    */
/* by the foregoing limitations and restrictions. Thank you.                       */  
/*                                                                                 */  

`timescale 1ns/1ps
`celldefine

module S018V3EBCDSP_X8Y4D128_PR(
                          Q,
			  CLK,
			  CEN,
			  WEN,
			  A,
			  D);

  parameter	Bits = 128;
  parameter	Word_Depth = 32;
  parameter	Add_Width = 5;

  output [Bits-1:0]      	Q;
  input		   		CLK;
  input		   		CEN;
  input		   		WEN;
  input	[Add_Width-1:0] 	A;
  input	[Bits-1:0] 		D;

  wire [Bits-1:0] 	Q_int;
  wire [Add_Width-1:0] 	A_int;
  wire                 	CLK_int;
  wire                 	CEN_int;
  wire                 	WEN_int;
  wire [Bits-1:0] 	D_int;

  reg  [Bits-1:0] 	Q_latched;
  reg  [Add_Width-1:0] 	A_latched;
  reg  [Bits-1:0] 	D_latched;
  reg                  	CEN_latched;
  reg                  	LAST_CLK;
  reg                  	WEN_latched;

  reg 			A0_flag;
  reg 			A1_flag;
  reg 			A2_flag;
  reg 			A3_flag;
  reg 			A4_flag;

  reg                	CEN_flag;
  reg                   CLK_CYC_flag;
  reg                   CLK_H_flag;
  reg                   CLK_L_flag;

  reg 			D0_flag;
  reg 			D1_flag;
  reg 			D2_flag;
  reg 			D3_flag;
  reg 			D4_flag;
  reg 			D5_flag;
  reg 			D6_flag;
  reg 			D7_flag;
  reg 			D8_flag;
  reg 			D9_flag;
  reg 			D10_flag;
  reg 			D11_flag;
  reg 			D12_flag;
  reg 			D13_flag;
  reg 			D14_flag;
  reg 			D15_flag;
  reg 			D16_flag;
  reg 			D17_flag;
  reg 			D18_flag;
  reg 			D19_flag;
  reg 			D20_flag;
  reg 			D21_flag;
  reg 			D22_flag;
  reg 			D23_flag;
  reg 			D24_flag;
  reg 			D25_flag;
  reg 			D26_flag;
  reg 			D27_flag;
  reg 			D28_flag;
  reg 			D29_flag;
  reg 			D30_flag;
  reg 			D31_flag;
  reg 			D32_flag;
  reg 			D33_flag;
  reg 			D34_flag;
  reg 			D35_flag;
  reg 			D36_flag;
  reg 			D37_flag;
  reg 			D38_flag;
  reg 			D39_flag;
  reg 			D40_flag;
  reg 			D41_flag;
  reg 			D42_flag;
  reg 			D43_flag;
  reg 			D44_flag;
  reg 			D45_flag;
  reg 			D46_flag;
  reg 			D47_flag;
  reg 			D48_flag;
  reg 			D49_flag;
  reg 			D50_flag;
  reg 			D51_flag;
  reg 			D52_flag;
  reg 			D53_flag;
  reg 			D54_flag;
  reg 			D55_flag;
  reg 			D56_flag;
  reg 			D57_flag;
  reg 			D58_flag;
  reg 			D59_flag;
  reg 			D60_flag;
  reg 			D61_flag;
  reg 			D62_flag;
  reg 			D63_flag;
  reg 			D64_flag;
  reg 			D65_flag;
  reg 			D66_flag;
  reg 			D67_flag;
  reg 			D68_flag;
  reg 			D69_flag;
  reg 			D70_flag;
  reg 			D71_flag;
  reg 			D72_flag;
  reg 			D73_flag;
  reg 			D74_flag;
  reg 			D75_flag;
  reg 			D76_flag;
  reg 			D77_flag;
  reg 			D78_flag;
  reg 			D79_flag;
  reg 			D80_flag;
  reg 			D81_flag;
  reg 			D82_flag;
  reg 			D83_flag;
  reg 			D84_flag;
  reg 			D85_flag;
  reg 			D86_flag;
  reg 			D87_flag;
  reg 			D88_flag;
  reg 			D89_flag;
  reg 			D90_flag;
  reg 			D91_flag;
  reg 			D92_flag;
  reg 			D93_flag;
  reg 			D94_flag;
  reg 			D95_flag;
  reg 			D96_flag;
  reg 			D97_flag;
  reg 			D98_flag;
  reg 			D99_flag;
  reg 			D100_flag;
  reg 			D101_flag;
  reg 			D102_flag;
  reg 			D103_flag;
  reg 			D104_flag;
  reg 			D105_flag;
  reg 			D106_flag;
  reg 			D107_flag;
  reg 			D108_flag;
  reg 			D109_flag;
  reg 			D110_flag;
  reg 			D111_flag;
  reg 			D112_flag;
  reg 			D113_flag;
  reg 			D114_flag;
  reg 			D115_flag;
  reg 			D116_flag;
  reg 			D117_flag;
  reg 			D118_flag;
  reg 			D119_flag;
  reg 			D120_flag;
  reg 			D121_flag;
  reg 			D122_flag;
  reg 			D123_flag;
  reg 			D124_flag;
  reg 			D125_flag;
  reg 			D126_flag;
  reg 			D127_flag;

  reg                   WEN_flag; 
  reg [Add_Width-1:0]   A_flag;
  reg [Bits-1:0]        D_flag;
  reg                   LAST_CEN_flag;
  reg                   LAST_WEN_flag;
  reg [Add_Width-1:0]   LAST_A_flag;
  reg [Bits-1:0]        LAST_D_flag;

  reg                   LAST_CLK_CYC_flag;
  reg                   LAST_CLK_H_flag;
  reg                   LAST_CLK_L_flag;

  wire                  CE_flag;
  wire                  WR_flag;
  reg    [Bits-1:0] 	mem_array[Word_Depth-1:0];

  integer      i;
  integer      n;

  buf dout_buf[Bits-1:0] (Q, Q_int);
  buf (CLK_int, CLK);
  buf (CEN_int, CEN);
  buf (WEN_int, WEN);
  buf a_buf[Add_Width-1:0] (A_int, A);
  buf din_buf[Bits-1:0] (D_int, D);   

  assign Q_int=Q_latched;
  assign CE_flag=!CEN_int;
  assign WR_flag=(!CEN_int && !WEN_int);

  always @(CLK_int)
    begin
      casez({LAST_CLK, CLK_int})
        2'b01: begin
          CEN_latched = CEN_int;
          WEN_latched = WEN_int;
          A_latched = A_int;
          D_latched = D_int;
          rw_mem;
        end
        2'b10,
        2'bx?,
        2'b00,
        2'b11: ;
        2'b?x: begin
	  for(i=0;i<Word_Depth;i=i+1)
    	    mem_array[i]={Bits{1'bx}};
    	  Q_latched={Bits{1'bx}};
          rw_mem;
          end
      endcase
    LAST_CLK=CLK_int;
   end

  always @(CEN_flag
           	or WEN_flag
		or A0_flag
		or A1_flag
		or A2_flag
		or A3_flag
		or A4_flag
		or D0_flag
		or D1_flag
		or D2_flag
		or D3_flag
		or D4_flag
		or D5_flag
		or D6_flag
		or D7_flag
		or D8_flag
		or D9_flag
		or D10_flag
		or D11_flag
		or D12_flag
		or D13_flag
		or D14_flag
		or D15_flag
		or D16_flag
		or D17_flag
		or D18_flag
		or D19_flag
		or D20_flag
		or D21_flag
		or D22_flag
		or D23_flag
		or D24_flag
		or D25_flag
		or D26_flag
		or D27_flag
		or D28_flag
		or D29_flag
		or D30_flag
		or D31_flag
		or D32_flag
		or D33_flag
		or D34_flag
		or D35_flag
		or D36_flag
		or D37_flag
		or D38_flag
		or D39_flag
		or D40_flag
		or D41_flag
		or D42_flag
		or D43_flag
		or D44_flag
		or D45_flag
		or D46_flag
		or D47_flag
		or D48_flag
		or D49_flag
		or D50_flag
		or D51_flag
		or D52_flag
		or D53_flag
		or D54_flag
		or D55_flag
		or D56_flag
		or D57_flag
		or D58_flag
		or D59_flag
		or D60_flag
		or D61_flag
		or D62_flag
		or D63_flag
		or D64_flag
		or D65_flag
		or D66_flag
		or D67_flag
		or D68_flag
		or D69_flag
		or D70_flag
		or D71_flag
		or D72_flag
		or D73_flag
		or D74_flag
		or D75_flag
		or D76_flag
		or D77_flag
		or D78_flag
		or D79_flag
		or D80_flag
		or D81_flag
		or D82_flag
		or D83_flag
		or D84_flag
		or D85_flag
		or D86_flag
		or D87_flag
		or D88_flag
		or D89_flag
		or D90_flag
		or D91_flag
		or D92_flag
		or D93_flag
		or D94_flag
		or D95_flag
		or D96_flag
		or D97_flag
		or D98_flag
		or D99_flag
		or D100_flag
		or D101_flag
		or D102_flag
		or D103_flag
		or D104_flag
		or D105_flag
		or D106_flag
		or D107_flag
		or D108_flag
		or D109_flag
		or D110_flag
		or D111_flag
		or D112_flag
		or D113_flag
		or D114_flag
		or D115_flag
		or D116_flag
		or D117_flag
		or D118_flag
		or D119_flag
		or D120_flag
		or D121_flag
		or D122_flag
		or D123_flag
		or D124_flag
		or D125_flag
		or D126_flag
		or D127_flag
           	or CLK_CYC_flag
           	or CLK_H_flag
           	or CLK_L_flag)
    begin
      update_flag_bus;
      CEN_latched = (CEN_flag!==LAST_CEN_flag) ? 1'bx : CEN_latched ;
      WEN_latched = (WEN_flag!==LAST_WEN_flag) ? 1'bx : WEN_latched ;
      for (n=0; n<Add_Width; n=n+1)
      A_latched[n] = (A_flag[n]!==LAST_A_flag[n]) ? 1'bx : A_latched[n] ;
      for (n=0; n<Bits; n=n+1)
      D_latched[n] = (D_flag[n]!==LAST_D_flag[n]) ? 1'bx : D_latched[n] ;
      LAST_CEN_flag = CEN_flag;
      LAST_WEN_flag = WEN_flag;
      LAST_A_flag = A_flag;
      LAST_D_flag = D_flag;
      LAST_CLK_CYC_flag = CLK_CYC_flag;
      LAST_CLK_H_flag = CLK_H_flag;
      LAST_CLK_L_flag = CLK_L_flag;
      rw_mem;
   end
      
  task rw_mem;
    begin
      if(CEN_latched==1'b0)
        begin
	  if(WEN_latched==1'b1) 	
   	    begin
   	      if(^(A_latched)==1'bx)
   	        Q_latched={Bits{1'bx}};
   	      else
		Q_latched=mem_array[A_latched];
       	    end
          else if(WEN_latched==1'b0)
   	    begin
   	      if(^(A_latched)==1'bx)
   	        begin
                  x_mem;
   	          Q_latched={Bits{1'bx}};
   	        end   	        
   	      else
		begin
   	          mem_array[A_latched]=D_latched;
   	          Q_latched=mem_array[A_latched];
   	        end
   	    end
	  else 
     	    begin
   	      Q_latched={Bits{1'bx}};
   	      if(^(A_latched)===1'bx)
                for(i=0;i<Word_Depth;i=i+1)
   		  mem_array[i]={Bits{1'bx}};   	        
              else
		mem_array[A_latched]={Bits{1'bx}};
   	    end
	end  	    	    
      else if(CEN_latched===1'bx)
        begin
	  if(WEN_latched===1'b1)
   	    Q_latched={Bits{1'bx}};
	  else 
	    begin
   	      Q_latched={Bits{1'bx}};
	      if(^(A_latched)===1'bx)
                x_mem;
              else
		mem_array[A_latched]={Bits{1'bx}};
   	    end	      	    	  
        end
    end
  endtask
      
   task x_mem;
   begin
     for(i=0;i<Word_Depth;i=i+1)
     mem_array[i]={Bits{1'bx}};
   end
   endtask

  task update_flag_bus;
  begin
    A_flag = {
		A4_flag,
		A3_flag,
		A2_flag,
		A1_flag,
            A0_flag};
    D_flag = {
		D127_flag,
		D126_flag,
		D125_flag,
		D124_flag,
		D123_flag,
		D122_flag,
		D121_flag,
		D120_flag,
		D119_flag,
		D118_flag,
		D117_flag,
		D116_flag,
		D115_flag,
		D114_flag,
		D113_flag,
		D112_flag,
		D111_flag,
		D110_flag,
		D109_flag,
		D108_flag,
		D107_flag,
		D106_flag,
		D105_flag,
		D104_flag,
		D103_flag,
		D102_flag,
		D101_flag,
		D100_flag,
		D99_flag,
		D98_flag,
		D97_flag,
		D96_flag,
		D95_flag,
		D94_flag,
		D93_flag,
		D92_flag,
		D91_flag,
		D90_flag,
		D89_flag,
		D88_flag,
		D87_flag,
		D86_flag,
		D85_flag,
		D84_flag,
		D83_flag,
		D82_flag,
		D81_flag,
		D80_flag,
		D79_flag,
		D78_flag,
		D77_flag,
		D76_flag,
		D75_flag,
		D74_flag,
		D73_flag,
		D72_flag,
		D71_flag,
		D70_flag,
		D69_flag,
		D68_flag,
		D67_flag,
		D66_flag,
		D65_flag,
		D64_flag,
		D63_flag,
		D62_flag,
		D61_flag,
		D60_flag,
		D59_flag,
		D58_flag,
		D57_flag,
		D56_flag,
		D55_flag,
		D54_flag,
		D53_flag,
		D52_flag,
		D51_flag,
		D50_flag,
		D49_flag,
		D48_flag,
		D47_flag,
		D46_flag,
		D45_flag,
		D44_flag,
		D43_flag,
		D42_flag,
		D41_flag,
		D40_flag,
		D39_flag,
		D38_flag,
		D37_flag,
		D36_flag,
		D35_flag,
		D34_flag,
		D33_flag,
		D32_flag,
		D31_flag,
		D30_flag,
		D29_flag,
		D28_flag,
		D27_flag,
		D26_flag,
		D25_flag,
		D24_flag,
		D23_flag,
		D22_flag,
		D21_flag,
		D20_flag,
		D19_flag,
		D18_flag,
		D17_flag,
		D16_flag,
		D15_flag,
		D14_flag,
		D13_flag,
		D12_flag,
		D11_flag,
		D10_flag,
		D9_flag,
		D8_flag,
		D7_flag,
		D6_flag,
		D5_flag,
		D4_flag,
		D3_flag,
		D2_flag,
		D1_flag,
            D0_flag};
   end
   endtask

  specify
    (posedge CLK => (Q[0] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[1] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[2] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[3] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[4] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[5] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[6] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[7] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[8] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[9] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[10] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[11] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[12] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[13] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[14] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[15] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[16] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[17] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[18] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[19] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[20] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[21] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[22] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[23] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[24] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[25] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[26] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[27] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[28] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[29] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[30] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[31] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[32] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[33] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[34] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[35] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[36] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[37] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[38] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[39] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[40] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[41] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[42] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[43] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[44] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[45] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[46] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[47] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[48] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[49] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[50] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[51] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[52] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[53] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[54] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[55] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[56] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[57] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[58] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[59] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[60] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[61] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[62] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[63] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[64] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[65] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[66] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[67] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[68] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[69] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[70] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[71] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[72] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[73] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[74] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[75] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[76] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[77] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[78] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[79] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[80] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[81] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[82] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[83] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[84] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[85] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[86] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[87] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[88] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[89] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[90] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[91] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[92] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[93] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[94] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[95] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[96] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[97] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[98] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[99] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[100] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[101] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[102] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[103] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[104] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[105] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[106] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[107] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[108] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[109] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[110] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[111] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[112] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[113] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[114] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[115] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[116] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[117] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[118] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[119] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[120] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[121] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[122] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[123] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[124] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[125] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[126] : 1'bx))=(1.000,1.000);
    (posedge CLK => (Q[127] : 1'bx))=(1.000,1.000);
    $setuphold(posedge CLK &&& CE_flag,posedge A[0],0.500,0.250,A0_flag);
    $setuphold(posedge CLK &&& CE_flag,negedge A[0],0.500,0.250,A0_flag);
    $setuphold(posedge CLK &&& CE_flag,posedge A[1],0.500,0.250,A1_flag);
    $setuphold(posedge CLK &&& CE_flag,negedge A[1],0.500,0.250,A1_flag);
    $setuphold(posedge CLK &&& CE_flag,posedge A[2],0.500,0.250,A2_flag);
    $setuphold(posedge CLK &&& CE_flag,negedge A[2],0.500,0.250,A2_flag);
    $setuphold(posedge CLK &&& CE_flag,posedge A[3],0.500,0.250,A3_flag);
    $setuphold(posedge CLK &&& CE_flag,negedge A[3],0.500,0.250,A3_flag);
    $setuphold(posedge CLK &&& CE_flag,posedge A[4],0.500,0.250,A4_flag);
    $setuphold(posedge CLK &&& CE_flag,negedge A[4],0.500,0.250,A4_flag);
    $setuphold(posedge CLK,posedge CEN,0.500,0.250,CEN_flag);
    $setuphold(posedge CLK,negedge CEN,0.500,0.250,CEN_flag);
    $period(posedge CLK,3.609,CLK_CYC_flag);
    $width(posedge CLK,1.083,0,CLK_H_flag);
    $width(negedge CLK,1.083,0,CLK_L_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[0],0.500,0.250,D0_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[0],0.500,0.250,D0_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[1],0.500,0.250,D1_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[1],0.500,0.250,D1_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[2],0.500,0.250,D2_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[2],0.500,0.250,D2_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[3],0.500,0.250,D3_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[3],0.500,0.250,D3_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[4],0.500,0.250,D4_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[4],0.500,0.250,D4_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[5],0.500,0.250,D5_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[5],0.500,0.250,D5_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[6],0.500,0.250,D6_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[6],0.500,0.250,D6_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[7],0.500,0.250,D7_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[7],0.500,0.250,D7_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[8],0.500,0.250,D8_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[8],0.500,0.250,D8_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[9],0.500,0.250,D9_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[9],0.500,0.250,D9_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[10],0.500,0.250,D10_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[10],0.500,0.250,D10_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[11],0.500,0.250,D11_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[11],0.500,0.250,D11_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[12],0.500,0.250,D12_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[12],0.500,0.250,D12_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[13],0.500,0.250,D13_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[13],0.500,0.250,D13_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[14],0.500,0.250,D14_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[14],0.500,0.250,D14_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[15],0.500,0.250,D15_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[15],0.500,0.250,D15_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[16],0.500,0.250,D16_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[16],0.500,0.250,D16_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[17],0.500,0.250,D17_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[17],0.500,0.250,D17_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[18],0.500,0.250,D18_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[18],0.500,0.250,D18_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[19],0.500,0.250,D19_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[19],0.500,0.250,D19_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[20],0.500,0.250,D20_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[20],0.500,0.250,D20_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[21],0.500,0.250,D21_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[21],0.500,0.250,D21_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[22],0.500,0.250,D22_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[22],0.500,0.250,D22_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[23],0.500,0.250,D23_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[23],0.500,0.250,D23_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[24],0.500,0.250,D24_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[24],0.500,0.250,D24_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[25],0.500,0.250,D25_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[25],0.500,0.250,D25_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[26],0.500,0.250,D26_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[26],0.500,0.250,D26_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[27],0.500,0.250,D27_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[27],0.500,0.250,D27_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[28],0.500,0.250,D28_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[28],0.500,0.250,D28_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[29],0.500,0.250,D29_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[29],0.500,0.250,D29_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[30],0.500,0.250,D30_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[30],0.500,0.250,D30_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[31],0.500,0.250,D31_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[31],0.500,0.250,D31_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[32],0.500,0.250,D32_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[32],0.500,0.250,D32_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[33],0.500,0.250,D33_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[33],0.500,0.250,D33_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[34],0.500,0.250,D34_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[34],0.500,0.250,D34_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[35],0.500,0.250,D35_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[35],0.500,0.250,D35_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[36],0.500,0.250,D36_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[36],0.500,0.250,D36_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[37],0.500,0.250,D37_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[37],0.500,0.250,D37_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[38],0.500,0.250,D38_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[38],0.500,0.250,D38_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[39],0.500,0.250,D39_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[39],0.500,0.250,D39_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[40],0.500,0.250,D40_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[40],0.500,0.250,D40_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[41],0.500,0.250,D41_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[41],0.500,0.250,D41_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[42],0.500,0.250,D42_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[42],0.500,0.250,D42_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[43],0.500,0.250,D43_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[43],0.500,0.250,D43_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[44],0.500,0.250,D44_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[44],0.500,0.250,D44_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[45],0.500,0.250,D45_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[45],0.500,0.250,D45_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[46],0.500,0.250,D46_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[46],0.500,0.250,D46_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[47],0.500,0.250,D47_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[47],0.500,0.250,D47_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[48],0.500,0.250,D48_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[48],0.500,0.250,D48_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[49],0.500,0.250,D49_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[49],0.500,0.250,D49_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[50],0.500,0.250,D50_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[50],0.500,0.250,D50_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[51],0.500,0.250,D51_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[51],0.500,0.250,D51_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[52],0.500,0.250,D52_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[52],0.500,0.250,D52_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[53],0.500,0.250,D53_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[53],0.500,0.250,D53_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[54],0.500,0.250,D54_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[54],0.500,0.250,D54_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[55],0.500,0.250,D55_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[55],0.500,0.250,D55_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[56],0.500,0.250,D56_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[56],0.500,0.250,D56_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[57],0.500,0.250,D57_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[57],0.500,0.250,D57_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[58],0.500,0.250,D58_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[58],0.500,0.250,D58_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[59],0.500,0.250,D59_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[59],0.500,0.250,D59_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[60],0.500,0.250,D60_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[60],0.500,0.250,D60_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[61],0.500,0.250,D61_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[61],0.500,0.250,D61_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[62],0.500,0.250,D62_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[62],0.500,0.250,D62_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[63],0.500,0.250,D63_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[63],0.500,0.250,D63_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[64],0.500,0.250,D64_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[64],0.500,0.250,D64_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[65],0.500,0.250,D65_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[65],0.500,0.250,D65_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[66],0.500,0.250,D66_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[66],0.500,0.250,D66_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[67],0.500,0.250,D67_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[67],0.500,0.250,D67_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[68],0.500,0.250,D68_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[68],0.500,0.250,D68_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[69],0.500,0.250,D69_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[69],0.500,0.250,D69_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[70],0.500,0.250,D70_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[70],0.500,0.250,D70_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[71],0.500,0.250,D71_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[71],0.500,0.250,D71_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[72],0.500,0.250,D72_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[72],0.500,0.250,D72_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[73],0.500,0.250,D73_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[73],0.500,0.250,D73_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[74],0.500,0.250,D74_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[74],0.500,0.250,D74_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[75],0.500,0.250,D75_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[75],0.500,0.250,D75_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[76],0.500,0.250,D76_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[76],0.500,0.250,D76_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[77],0.500,0.250,D77_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[77],0.500,0.250,D77_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[78],0.500,0.250,D78_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[78],0.500,0.250,D78_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[79],0.500,0.250,D79_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[79],0.500,0.250,D79_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[80],0.500,0.250,D80_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[80],0.500,0.250,D80_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[81],0.500,0.250,D81_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[81],0.500,0.250,D81_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[82],0.500,0.250,D82_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[82],0.500,0.250,D82_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[83],0.500,0.250,D83_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[83],0.500,0.250,D83_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[84],0.500,0.250,D84_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[84],0.500,0.250,D84_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[85],0.500,0.250,D85_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[85],0.500,0.250,D85_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[86],0.500,0.250,D86_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[86],0.500,0.250,D86_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[87],0.500,0.250,D87_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[87],0.500,0.250,D87_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[88],0.500,0.250,D88_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[88],0.500,0.250,D88_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[89],0.500,0.250,D89_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[89],0.500,0.250,D89_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[90],0.500,0.250,D90_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[90],0.500,0.250,D90_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[91],0.500,0.250,D91_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[91],0.500,0.250,D91_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[92],0.500,0.250,D92_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[92],0.500,0.250,D92_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[93],0.500,0.250,D93_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[93],0.500,0.250,D93_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[94],0.500,0.250,D94_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[94],0.500,0.250,D94_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[95],0.500,0.250,D95_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[95],0.500,0.250,D95_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[96],0.500,0.250,D96_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[96],0.500,0.250,D96_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[97],0.500,0.250,D97_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[97],0.500,0.250,D97_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[98],0.500,0.250,D98_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[98],0.500,0.250,D98_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[99],0.500,0.250,D99_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[99],0.500,0.250,D99_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[100],0.500,0.250,D100_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[100],0.500,0.250,D100_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[101],0.500,0.250,D101_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[101],0.500,0.250,D101_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[102],0.500,0.250,D102_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[102],0.500,0.250,D102_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[103],0.500,0.250,D103_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[103],0.500,0.250,D103_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[104],0.500,0.250,D104_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[104],0.500,0.250,D104_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[105],0.500,0.250,D105_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[105],0.500,0.250,D105_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[106],0.500,0.250,D106_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[106],0.500,0.250,D106_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[107],0.500,0.250,D107_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[107],0.500,0.250,D107_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[108],0.500,0.250,D108_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[108],0.500,0.250,D108_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[109],0.500,0.250,D109_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[109],0.500,0.250,D109_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[110],0.500,0.250,D110_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[110],0.500,0.250,D110_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[111],0.500,0.250,D111_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[111],0.500,0.250,D111_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[112],0.500,0.250,D112_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[112],0.500,0.250,D112_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[113],0.500,0.250,D113_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[113],0.500,0.250,D113_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[114],0.500,0.250,D114_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[114],0.500,0.250,D114_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[115],0.500,0.250,D115_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[115],0.500,0.250,D115_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[116],0.500,0.250,D116_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[116],0.500,0.250,D116_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[117],0.500,0.250,D117_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[117],0.500,0.250,D117_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[118],0.500,0.250,D118_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[118],0.500,0.250,D118_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[119],0.500,0.250,D119_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[119],0.500,0.250,D119_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[120],0.500,0.250,D120_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[120],0.500,0.250,D120_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[121],0.500,0.250,D121_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[121],0.500,0.250,D121_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[122],0.500,0.250,D122_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[122],0.500,0.250,D122_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[123],0.500,0.250,D123_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[123],0.500,0.250,D123_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[124],0.500,0.250,D124_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[124],0.500,0.250,D124_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[125],0.500,0.250,D125_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[125],0.500,0.250,D125_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[126],0.500,0.250,D126_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[126],0.500,0.250,D126_flag);
    $setuphold(posedge CLK &&& WR_flag,posedge D[127],0.500,0.250,D127_flag);
    $setuphold(posedge CLK &&& WR_flag,negedge D[127],0.500,0.250,D127_flag);
    $setuphold(posedge CLK &&& CE_flag,posedge WEN,0.500,0.250,WEN_flag);
    $setuphold(posedge CLK &&& CE_flag,negedge WEN,0.500,0.250,WEN_flag);
  endspecify

endmodule

`endcelldefine