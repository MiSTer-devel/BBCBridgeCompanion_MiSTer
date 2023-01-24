`timescale 1ns / 1ns

module interrupt(RESET, DI, IORQ_n, RD_n, M1_n, IEI, IEO, INTO_n, VECTEN, INTI, INTEN);
   input       RESET;
   input [7:0] DI;
   input       IORQ_n;
   input       RD_n;
   input       M1_n;
   input       IEI;
   output      IEO;
   output      INTO_n;
   output      VECTEN;
   input       INTI;
   input       INTEN;
   
   
   reg         IREQ;
   wire        IRES;
   wire        INTR;
   reg         IAUTH;
   wire        AUTHRES;
   reg         IED1;
   reg         IED2;
   reg         ICB;
   reg         I4D;
   wire        FETCH;
   wire        INTA;
   wire        IENB;
   wire        iINT;
   wire        iIEO;
   
   assign INTO_n = iINT;
   assign IEO = iIEO;
   
   assign iINT = (IEI == 1'b1 & IREQ == 1'b1 & IAUTH == 1'b0) ? 1'b0 : 
                 1'b1;
   assign iIEO = (~((((~IED1)) & IREQ) | IAUTH | ((~IEI))));
   assign INTA = (((~M1_n)) & ((~IORQ_n)) & IEI);
   assign AUTHRES = RESET | (IEI & IED2 & I4D);
   assign FETCH = M1_n | RD_n;
   assign IRES = RESET | INTA;
   assign INTR = M1_n & (INTI & INTEN);
   assign VECTEN = (INTA == 1'b1 & IEI == 1'b1 & IAUTH == 1'b1) ? 1'b1 : 
                   1'b0;
   
   
   always @(posedge IRES or posedge INTR)
      if (IRES == 1'b1)
         IREQ <= 1'b0;
      else 
         IREQ <= 1'b1;
   
   
   always @(posedge AUTHRES or posedge INTA)
      if (AUTHRES == 1'b1)
         IAUTH <= 1'b0;
      else 
         IAUTH <= IREQ;
   
   
   always @(posedge RESET or posedge FETCH)
      if (RESET == 1'b1)
      begin
         IED1 <= 1'b0;
         IED2 <= 1'b0;
         ICB <= 1'b0;
         I4D <= 1'b0;
      end
      else 
      begin
         IED2 <= IED1;
         if (DI == 8'hED & ICB == 1'b0)
            IED1 <= 1'b1;
         else
            IED1 <= 1'b0;
         if (DI == 8'hCB)
            ICB <= 1'b1;
         else
            ICB <= 1'b0;
         if (DI == 8'h4D)
            I4D <= IEI;
         else
            I4D <= 1'b0;
      end
   
endmodule
