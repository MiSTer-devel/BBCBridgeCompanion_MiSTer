// Zilog Z80PIO partiality compatible module
// Port A : Output, mode 0 only
// Port B : Input, mode 0 only
//
// Nibbles Lab. 2005-2014

`timescale 1ns / 1ns

module z8420(RST_n, CLK, ENA, BASEL, CDSEL, CE, RD_n, WR_n, IORQ_n, M1_n, DI, DO, IEI, IEO, INT_n, A, B);
   input        RST_n;
   input        CLK;
   input        ENA;
   input        BASEL;
   input        CDSEL;
   input        CE;
   input        RD_n;
   input        WR_n;
   input        IORQ_n;
   input        M1_n;
   input [7:0]  DI;
   output [7:0] DO;
   input        IEI;
   output       IEO;
   output       INT_n;
   output [7:0] A;
   input [7:0]  B;
   
   
   wire         SELAD;
   wire         SELBD;
   wire         SELAC;
   wire         SELBC;
   reg [7:0]    AREG;
   reg [7:0]    DIRA;
   reg          DDWA;
   reg [7:0]    IMWA;
   reg          MFA;
   reg [7:0]    VECTA;
   reg [1:0]    MODEA;
   reg          HLA;
   reg          AOA;
   reg [7:0]    DIRB;
   reg          DDWB;
   reg [7:0]    IMWB;
   reg          MFB;
   reg [7:0]    VECTB;
   reg [1:0]    MODEB;
   reg          HLB;
   reg          AOB;
   reg          EIA;
   wire         VECTENB;
   reg          EIB;
   wire [7:0]   MINTB;
   wire         INTB;
   
   
   interrupt INT1(
      .RESET(RST_n),
      .DI(DI),
      .IORQ_n(IORQ_n),
      .RD_n(RD_n),
      .M1_n(M1_n),
      .IEI(IEI),
      .IEO(IEO),
      .INTO_n(INT_n),
      .VECTEN(VECTENB),
      .INTI(INTB),
      .INTEN(EIB)
   );
   
   assign SELAD = (BASEL == 1'b0 & CDSEL == 1'b0) ? 1'b1 : 
                  1'b0;
   assign SELBD = (BASEL == 1'b1 & CDSEL == 1'b0) ? 1'b1 : 
                  1'b0;
   assign SELAC = (BASEL == 1'b0 & CDSEL == 1'b1) ? 1'b1 : 
                  1'b0;
   assign SELBC = (BASEL == 1'b1 & CDSEL == 1'b1) ? 1'b1 : 
                  1'b0;

   always @(negedge CLK)
      if (RST_n == 1'b0)
      begin
         AREG <= {8{1'b0}};
         MODEA <= 2'b01;
         DDWA <= 1'b0;
         MFA <= 1'b0;
         EIA <= 1'b0;
         MODEB <= 2'b01;
         DDWB <= 1'b0;
         MFB <= 1'b0;
         EIB <= 1'b0;
      end
      else 
      begin
         if (ENA == 1'b1)
         begin
            if (CE == 1'b0 & WR_n == 1'b0)
            begin
               if (SELAD == 1'b1)
               begin
                  AREG <= DI;
               end
               if (SELAC == 1'b1)
               begin
                  if (DDWA == 1'b1)
                  begin
                     DIRA <= DI;
                     DDWA <= 1'b0;
                  end
                  else if (MFA == 1'b1)
                  begin
                     IMWA <= DI;
                     MFA <= 1'b0;
                  end
                  else if (DI[0] == 1'b0)
                     VECTA <= DI;
                  else if (DI[3:0] == 4'b1111)
                  begin
                     MODEA <= DI[7:6];
                     DDWA <= DI[7] & DI[6];
                  end
                  else if (DI[3:0] == 4'b0111)
                  begin
                     MFA <= DI[4];
                     HLA <= DI[5];
                     AOA <= DI[6];
                     EIA <= DI[7];
                  end
                  else if (DI[3:0] == 4'b0011)
                     EIA <= DI[7];
               end
               if (SELBC == 1'b1)
               begin
                  if (DDWB == 1'b1)
                  begin
                     DIRB <= DI;
                     DDWB <= 1'b0;
                  end
                  else if (MFB == 1'b1)
                  begin
                     IMWB <= DI;
                     MFB <= 1'b0;
                  end
                  else if (DI[0] == 1'b0)
                     VECTB <= DI;
                  else if (DI[3:0] == 4'b1111)
                  begin
                     MODEB <= DI[7:6];
                     DDWB <= DI[7] & DI[6];
                  end
                  else if (DI[3:0] == 4'b0111)
                  begin
                     MFB <= DI[4];
                     HLB <= DI[5];
                     AOB <= DI[6];
                     EIB <= DI[7];
                  end
                  else if (DI[3:0] == 4'b0011)
                     EIB <= DI[7];
               end
            end
         end
      end
   assign A = AREG;
   
   assign DO = (RD_n == 1'b0 & CE == 1'b0 & SELAD == 1'b1) ? AREG : 
               (RD_n == 1'b0 & CE == 1'b0 & SELBD == 1'b1) ? B : 
               (VECTENB == 1'b1) ? VECTB : 
               {8{1'b0}};
   
   generate
      begin : xhdl0
         genvar       I;
         for (I = 0; I <= 7; I = I + 1)
         begin : INTMASK
            assign MINTB[I] = (AOB == 1'b0) ? (B[I] ~^ HLB) & ((~IMWB[I])) : 
                              (B[I] ~^ HLB) | IMWB[I];
         end
      end
   endgenerate
   assign INTB = (AOB == 1'b0) ? MINTB[7] | MINTB[6] | MINTB[5] | MINTB[4] | MINTB[3] | MINTB[2] | MINTB[1] | MINTB[0] : 
                 MINTB[7] & MINTB[6] & MINTB[5] & MINTB[4] & MINTB[3] & MINTB[2] & MINTB[1] & MINTB[0];
   
endmodule
