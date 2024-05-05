`timescale 1ns/1ps;

module Intel_8237A(A30, A30_oe, D, D_oe, HLDA, EOP_, EOP_oe, RESET, CLK,
IOR_MEMR_, IOR_MEMR_oe, IOW_MEMW_, IOW_MEMW_oe, READY, DREQ0, DREQ1, DREQ2, DREQ3,
HRQ, A74, ADSTB, AEN, DACK0, DACK1, DACK2, DACK3,
CS_, Vcc_GND);

/*1st-2nd line: input(-output)   3rd line: output   4th line: hardware configuration  */

inout[3:0] A30; // indirizzamento del chip (in)  +  generazione indirizzi (out)
reg[3:0] A30_reg;
input A30_oe;
assign A30 = (!CS_ && A30_oe) ? A30_reg : 4'hz;

inout[7:0] D; // per scambio dati su 8 bit (se AEN ha valore alto --> diventano A15-A8)
reg[7:0] D_reg;
input D_oe;
assign D = (!CS_ && D_oe) ? D_reg : 8'hzz;

input HLDA; // grant DA PARTE DEL PROCESSORE per l'accesso al bus  (HoLD Acknowledge)

inout EOP_; // End Of Process: in --> richiesta dall'esterno di terminare le operazioni 
            // out -->  presenza di una richiesta interna di terminare le operazioni
reg EOP_reg;
input EOP_oe;
assign EOP_ = (!CS_ && EOP_oe) ? EOP_reg : 1'bz;



input RESET;
input CLK;

inout[1:0] IOR_MEMR_; //Lettura da/verso I/O e/o da/verso memoria
input IOR_MEMR_oe;

inout[1:0] IOW_MEMW_; //Scrittura da/verso I/O e/o da/verso memoria
input IOW_MEMW_oe;

reg[1:0] IOR_MEMR_reg;
assign IOR_MEMR_ = (!CS_ && IOR_MEMR_oe) ? IOR_MEMR_reg : 2'bzz;

reg[1:0] IOW_MEMW_reg;
assign IOW_MEMW_ = (!CS_ && IOW_MEMW_oe) ? IOW_MEMW_reg : 2'bzz;

input READY; //attivato dal target: inizia il trasferimento solo quando READY è alto (analogo a WAIT)

//DREQ_i --> Usato dalla periferica i-esima per richiedere accesso al canale i-esimo del DMA e iniziare un trasferimento di dati. Notare
//che per il trasferimento viene usato un protocollo di handshake del tipo REQ-ACK
input DREQ0; 
input DREQ1;
input DREQ2;
input DREQ3;

wire[3:0] DREQ_wire;
assign DREQ_wire = {DREQ3, DREQ2, DREQ1, DREQ0};


output HRQ; // richiesta AL PROCESSORE di accesso al bus
reg HRQ_reg;
assign HRQ = HRQ_reg;



output[3:0] A74; //solo generazione indirizzi (out)
reg[3:0] A74_reg;
assign A74 = A74_reg;


output ADSTB; //memorizza su latch esterno A15-8 (cioè D7-D0)  (ADdress STroBe)
reg ADSTB_reg;
assign ADSTB = ADSTB_reg;


output AEN;  //abilita l'uso di D7-D0 come A15-A8  -->  Il sistema usa 16 bit di indirizzamento   (Address ENable)
reg AEN_reg;
assign AEN = AEN_reg;

wire[1:0] SERVED_CHANNEL;

//DACK_i --> Usato dal controller DMA per permettere l'accesso al canale i-esimo all periferica i-esima e iniziare un trasferimento di dati.
//Notare che per il trasferimento viene usato un protocollo di handshake del tipo REQ-ACK
output DACK0;
output DACK1;
output DACK2;
output DACK3;
reg DACK0_reg;
reg DACK1_reg;
reg DACK2_reg;
reg DACK3_reg;

assign DACK0 = DACK0_reg;
assign DACK1 = DACK1_reg;
assign DACK2 = DACK2_reg;
assign DACK3 = DACK3_reg;

wire[3:0] DACK_wire;
always @(negedge CLK) begin
    {DACK3_reg, DACK2_reg, DACK1_reg, DACK0_reg} = DACK_wire;
end



input CS_; // chip select: abilitazione del chip
input[1:0] Vcc_GND; // necessari solo per l'implementazione del circuito: non c'è scambio di dati

reg[7:0] TEMP; //temporary register

reg[7:0] CR; //Control Register
reg[7:0] SR; //Status Register
reg[7:0] MR; //Mode Register
reg[7:0] MKR; //MasK Register


reg[15:0] BADDR0; //base address 0
reg[15:0] BWC0; //base word count 0

reg[15:0] BADDR1; //base address 1 
reg[15:0] BWC1; //base word count 1

reg[15:0] BADDR2; //base address 2
reg[15:0] BWC2; //base word count 2

reg[15:0] BADDR3; //base address 3
reg[15:0] BWC3; //base word count 3


reg[15:0] CADDR0; //current address 0
reg[15:0] CWC0; //current word count 0 

reg[15:0] CADDR1; //current address 1 
reg[15:0] CWC1; //current word count 1

reg[15:0] CADDR2; //current address 2 
reg[15:0] CWC2; //current word count 2 

reg[15:0] CADDR3; //current address 3
reg[15:0] CWC3; //current word count 3

reg ULLATCH; //internal UPPER/LOWER latch to determine if upper or lower part of address is being sent   //1 --> UPPER   0 ---> LOWER

reg CHANNEL_LOCK;  // -->  changed via EOP_

reg[2:0] STATE;
parameter SI = 3'b111; //idle state
parameter S0 = 3'b000;  //ACKNOWLEDGE REQUESTED BUT NOT RECEIVED YET
parameter S1 = 3'b001; /*output the higher order address bits to an external latch
from which they may be placed on the address bus.*/
parameter S2 = 3'b010;  //transition to S3
parameter S3 = 3'b011;  //evaluate IOW and MEMW + send address to IO
parameter S4 = 3'b100;  //send data as output, then transition to S1 to evaluate if transfer should continue or end



//USAGE register has to be set-up at every time-step according to requests pending
reg[7:0] USAGE; //[1:0] --> priority value for DREQ0 ,  [3:2] --> DREQ1 , [5:4] --> DREQ2 , [7:6] --> DREQ3


    always @(posedge CLK) if (RESET == 1'b1 && CS_ == 0) begin

        EOP_reg <= 1'b0;

        ULLATCH <= 1'b0;

        CR[0] <= 1'b0; //memory-to-memory --> disabled
        CR[4] <= 1'b0; //fixed priority
        CR[7:5] <= 3'bxxx;
        CR[3:1] <= 3'bxxx;

        SR[7:0] <= 8'h00;

        MR[7:6] <= 2'b00; //demand mode
        MR[5:4] <= 2'bxx;
        MR[3:2] <= 2'b00; //channel 0, verify transfer mode

        MKR[7:4] <= 4'bxxxx;
        {DACK0_reg, DACK1_reg, DACK2_reg, DACK3_reg} <= 4'h0; //reset ack signals
        USAGE <= 8'b00000000; //reset priority
        ADSTB_reg <= 1'b0;

        MKR[3:0] <= 4'h0; //all requests disabled
        MR[1:0] <= 2'b00; //select channel 0
    end

    always @(posedge CLK) if (!(EOP_) && CS_ == 0) begin
        //invia interrupt all'interrupt controller
        $display("Interrupt inviato"); //simula invio interrupt ad interrupt controller
        MR[1:0] <= SERVED_CHANNEL;
        HRQ_reg <= 1'b0;

        if (SR[7] != 1'b0 || SR[6] != 1'b0 || SR[5] != 1'b0 ||  SR[4] != 1'b0) begin
            STATE <= S0;
            CHANNEL_LOCK <= 1'b0;
        end
        else begin 
            STATE <= SI;
            CHANNEL_LOCK <= 1'b0;
        end

        //update priority queue after process
        if (CR[4] == 1) begin
            casex(TEMP[5:4]) //use previous value of MR (stored in TEMP[5:4]) to update USAGE
            2'b00:
            begin
                USAGE[1:0] <= 2'b11;
                USAGE[3:2] <= (USAGE[3:2] == 2'b00) ? 2'b00 : (USAGE[3:2] - 2'b01);
                USAGE[5:4] <= (USAGE[5:4] == 2'b00) ? 2'b00 : (USAGE[5:4] - 2'b01);
                USAGE[7:6] <= (USAGE[7:6] == 2'b00) ? 2'b00 : (USAGE[7:6] - 2'b01);
            end
            2'b01:
            begin
                USAGE[1:0] <= (USAGE[1:0] == 2'b00) ? 2'b00 : (USAGE[1:0] - 2'b01);
                USAGE[3:2] <= 2'b11;
                USAGE[5:4] <= (USAGE[5:4] == 2'b00) ? 2'b00 : (USAGE[5:4] - 2'b01);
                USAGE[7:6] <= (USAGE[7:6] == 2'b00) ? 2'b00 : (USAGE[7:6] - 2'b01);
            end
            3'b10:
            begin
                USAGE[1:0] <= (USAGE[1:0] == 2'b00) ? 2'b00 : (USAGE[1:0] - 2'b01);
                USAGE[3:2] <= (USAGE[3:2] == 2'b00) ? 2'b00 : (USAGE[3:2] - 2'b01);
                USAGE[5:4] <= 2'b11;
                USAGE[7:6] <= (USAGE[7:6] == 2'b00) ? 2'b00 : (USAGE[7:6] - 2'b01);
            end
            3'b11:
            begin
                USAGE[1:0] <= (USAGE[1:0] == 2'b00) ? 2'b00 : (USAGE[1:0] - 2'b01);
                USAGE[3:2] <= (USAGE[3:2] == 2'b00) ? 2'b00 : (USAGE[3:2] - 2'b01);
                USAGE[5:4] <= (USAGE[5:4] == 2'b00) ? 2'b00 : (USAGE[5:4] - 2'b01);
                USAGE[7:6] <= 2'b11;
            end
            endcase
        end

        //End of EOP_ evaluation
        EOP_reg <= 1'b1;
    end


/*
#########################
#PROGRAMMAZIONE INIZIALE#
#########################
*/

/*Base Address e Base Word Count-->  Possono essere SCRITTI da CPU            Current Address e Current Word Count  -->  Possono essere LETTI da CPU*/
 
/*NOTA: Scrivere prima WC per determinare il numero di word da trasferire e IN SEGUITO inviare l'indirizzo a cui effettuare il trasferimento (NON è possibile riutilizzare un indirizzo già scritto dato che 
la priority enqueue è effettuata solo su scrittura di BA)*/

    always @(posedge CLK) if (STATE == SI && EOP_ == 1'b1 && (A30_oe == 1'b0) && CS_ == 0) begin
        casex((ULLATCH == 1) ? (TEMP[3:0]) : (A30)) //force second cycle with same value
            4'h0: begin 
                begin 
                    if (IOW_MEMW_[1] == 1'b0)  begin if (ULLATCH == 1'b0) begin BADDR0[7:0] <= D; CADDR0[7:0] <= D; ULLATCH <= 1'b1; end else begin BADDR0[15:8] <= D; CADDR0[15:8] <= D; ULLATCH <= 1'b0; end end else   
                                    begin D_reg  <=  (ULLATCH == 1'b1) ?  CADDR0[15:8] : CADDR0[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received ADDR0: %b  on DATA at %d\n", BADDR0, $time);
                end

                //only begin DMA transfer when ADDRESS MSB is being sent
                if (ULLATCH == 1'b0) begin 
                    SR[4] <= 1'b1;
                    if (HRQ_reg != 1'b1) STATE <= S0;
                    if (!(USAGE[1:0] == 2'b00)) //condizione iniziale
                    begin //per la gestione della politica di enqueue nella rotating priority
                        USAGE[1:0] <= (USAGE[7:2] == 6'h00) ? 2'b01  :  
                        ((USAGE[7:6] == 2'b01 || USAGE[5:4] == 2'b01 || USAGE[3:2] == 2'b01) && (USAGE[7:6] != 2'b10 && USAGE[5:4] != 2'b10 && USAGE[3:2] != 2'b10)) ? 2'b10  :
                         2'b11;
                    end
                end
            end 

            4'h1:
             begin 
                begin
                    if (IOW_MEMW_[1] == 1'b0) begin if (ULLATCH == 1'b0) begin BWC0[7:0] <= D; CWC0[7:0] <= D; ULLATCH <= 1'b1; end else begin BWC0[15:8] <= D; CWC0[15:8] <= D; ULLATCH <= 1'b0; end end 
                    else begin D_reg  <=  (ULLATCH == 1'b1) ?  CWC0[15:8] : CWC0[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received WC0: %b  on DATA\n", BWC0);
                end
            end


            4'h2: 
             begin 
                begin
                    if (IOW_MEMW_[1] == 1'b0)  begin if (ULLATCH == 1'b0) begin BADDR1[7:0] <= D; CADDR1[7:0] <= D; ULLATCH <= 1'b1; end else begin BADDR1[15:8] <= D; CADDR1[15:8] <= D; ULLATCH <= 1'b0; end end    
                                  else  begin D_reg  <=  (ULLATCH == 1'b1) ?  CADDR1[15:8] : CADDR1[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received ADDR1: %b  on DATA at %d\n", BADDR1, $time);
                end

                if (ULLATCH == 1'b0) begin 
                    SR[5] <= 1'b1;
                    if (HRQ_reg != 1'b1) STATE <= S0;
                    if (!(USAGE[3:2] == 2'b00)) //condizione iniziale
                    begin //per la gestione della politica di enqueue nella rotating priority
                        USAGE[3:2] <= (USAGE[7:4] == 4'h0 && USAGE[1:0] == 2'b00) ? 2'b01  :  
                        ((USAGE[7:6] == 2'b01 || USAGE[5:4] == 2'b01 || USAGE[1:0] == 2'b01) && (USAGE[7:6] != 2'b10 && USAGE[5:4] != 2'b10 && USAGE[1:0] != 2'b10)) ? 2'b10  :
                         2'b11;
                    end
                end
                end
            4'h3:  
            begin 
                    if (IOW_MEMW_[1] == 1'b0)  begin if (ULLATCH == 1'b0) begin BWC1[7:0] <= D; CWC1[7:0] <= D; ULLATCH <= 1'b1; end else begin BWC1[15:8] <= D; CWC1[15:8] <= D; ULLATCH <= 1'b0; end end   
                    else begin D_reg  <=  (ULLATCH == 1'b1) ?  CWC1[15:8] : CWC1[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received WC1: %b  on DATA  at %d\n", BWC1, $time);
            end


            4'h4:  
            begin 
                    if (IOW_MEMW_[1] == 1'b0)  begin if (ULLATCH == 1'b0) begin BADDR2[7:0] <= D; CADDR2[7:0] <= D; ULLATCH <= 1'b1; end else begin BADDR2[15:8] <= D; CADDR2[15:8] <= D;  ULLATCH <= 1'b0; end end  
                    else begin D_reg  <=  (ULLATCH == 1'b1) ?  CADDR2[15:8] : CADDR2[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received word: %b  on DATA\n", BADDR2);

                    if (ULLATCH == 1'b0) begin

                    SR[6] <= 1'b1;
                    STATE <= S0;
                    if (!(USAGE[5:4] == 2'b00)) //condizione iniziale
                    begin //per la gestione della politica di enqueue nella rotating priority
                        USAGE[5:4] <= (USAGE[7:6] == 2'b00 && USAGE[3:0] == 4'h0) ? 2'b01  :  
                        ((USAGE[7:6] == 2'b01 || USAGE[1:0] == 2'b01 || USAGE[3:2] == 2'b01) && (USAGE[7:6] != 2'b10 && USAGE[1:0] != 2'b10 && USAGE[3:2] != 2'b10)) ? 2'b10  : 2'b11;
                    end
                end
            end

            4'h5: 
             begin 
                    if (IOW_MEMW_[1] == 1'b0) begin if (ULLATCH == 1'b0) begin BWC2[7:0] <= D; CWC2[7:0] <= D; ULLATCH <= 1'b1; end else begin BWC2[15:8] <= D; CWC0[15:8] <= D;  ULLATCH <= 1'b0; end end  
                    else begin D_reg  <=  (ULLATCH == 1'b1) ?  CWC2[15:8] : CWC2[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received word: %b  on DATA\n", BWC2);
                end


            4'h6:  
            begin 
                    if (IOW_MEMW_[1]) begin if (ULLATCH == 1'b0) begin BADDR3[7:0] <= D; CADDR3[7:0] <= D; ULLATCH <= 1'b1; end else begin BADDR3[15:8] <= D; CADDR3[15:8] <= D;  ULLATCH <= 1'b0; end end   
                    else begin D_reg  <=  (ULLATCH == 1'b1) ?  CADDR3[15:8] : CADDR3[7:0]; if (ULLATCH == 1'b0) ULLATCH <= 1'b1; else ULLATCH <= 1'b0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received word: %b  on DATA\n", BADDR3);

                    if (ULLATCH == 1'b0) begin
                    SR[7] <= 1'b1;
                    STATE <= S0;
                    if (!(USAGE[7:6] == 2'b00)) //condizione iniziale
                    begin //per la gestione della politica di enqueue nella rotating priority
                        USAGE[7:6] <= (USAGE[5:0] == 6'h00) ? 2'b01  :  
                        ((USAGE[1:0] == 2'b01 || USAGE[5:4] == 2'b01 || USAGE[3:2] == 2'b01) && (USAGE[1:0] != 2'b10 && USAGE[5:4] != 2'b10 && USAGE[3:2] != 2'b10)) ? 2'b10  :
                        2'b11;
                    end
                end
            end
            4'h7:  
            begin 
                    if (IOW_MEMW_[1]) begin if (ULLATCH == 1'b0) begin BWC3[7:0] <= D; CWC3[7:0] <= D; ULLATCH <= 1'b1; end else begin BWC3[15:8] <= D; CWC3[15:8] <= D; ULLATCH <= 1'b0; end end 
                    else begin D_reg  <=  (ULLATCH == 1) ?  CWC3[15:8] : CWC3[7:0]; if (ULLATCH == 0) ULLATCH <= 1; else ULLATCH <= 0; end
                    
                    TEMP[3:0] <= A30;
                    //#1 $display("Received word: %b  on DATA\n", BWC3);
                end

            4'hC: ULLATCH <= 1'b0; //Clear-Byte-Pointer-Flip-Flop


            4'h8: begin if (IOW_MEMW_[1] == 1'b0) CR <= D; else D_reg <= SR; /*#1 $display("Received CR: %b  on DATA\n", CR);*/ end //in caso di scrittura, scrivo su CR; in caso di lettura, leggo SR
            4'hB: begin if (IOW_MEMW_[1] == 1'b0)  MR <= D; /*#1 $display("Received MR: %b  on DATA\n", MR);*/ end 
            4'hF: begin if(IOW_MEMW_[1] == 1'b0) MKR <= D; /*#1 $display("Received MKR: %b  on DATA\n", MKR);*/ end  
        endcase
        
    end


/*
#######################################
#GESTIONE TRASFERIMENTI (active cycle)#
#######################################
*/

    always @(negedge CLK) if (EOP_ == 1'b1 && ((STATE == S0 || STATE == S1 || STATE == S2 || STATE == S3 || STATE == S4) || (HRQ_reg == 1 && STATE == SI)) && CS_ == 0) begin
        MR[1:0] <= SERVED_CHANNEL;
        if (!(HLDA == 1 && HRQ == 0)) begin
            //enable channel lock
            if (HRQ_reg == 1) begin MR[7:6] <= TEMP[7:6]; MR[1:0] <= TEMP[5:4]; end
            if (CHANNEL_LOCK == 1'b0) CHANNEL_LOCK = 1'b1;
            casex(MR[7:6])         //Select Transfer Mode
                2'b00: //demand mode    --->   NON USA WORD COUNTER (stop al transfer quando DREQi = 0)
                    casex((SERVED_CHANNEL == 2'bxx) ? MR[1:0] : TEMP[5:4]) //select port
                        2'b00: 
                        begin
                            if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                    if (HLDA == 1'b1) begin 
                                        //modalità operativa del DMAC (active state)
                                        if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from Channel 0");*/ end //Special SI state --> after S0

                                        if (STATE == S1 && ADSTB == 1'b0) begin
                                                    if (HRQ_reg == 1) begin
                                                        if (DREQ0 == 1'b0) begin
                                                            CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                            HRQ_reg <= 1'b0;
                                                            EOP_reg <= 1'b0; //interrupt fine processo
                                                            SR[4] <= 1'b0;  //disable channel 0
                                                            SR[0] <= 1'b1; //conteggio terminato per channel 0
                                                                            //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                        end else begin
                                                            if (CADDR0[7:4] == 4'hF || CADDR0[7:4] == 4'h0) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                            STATE <= S2;
                                                        end
                                                        
                                                    end 
                                                    else begin 
                                                    STATE <= SI;
                                                    end
                                        end

                                        if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                            if (STATE == S2) begin /*$display("Entered S2 from Channel 0");*/ STATE <= S3; end else if (STATE == S3) begin 
                                                //$display("Entered S3 from CHannel 0:");

                                                IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                AEN_reg <= 1; //enable D to send address
                                                {D_reg, A74_reg, A30_reg} <= CADDR0; //invio indirizzo

                                                if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                    ADSTB_reg <= 0;
                                                end

                                            end
                                        end
                                        end
                                        else if (STATE == S0) begin 
                                            //$display("Channel 0 entered S0, it will SI");
                                            HRQ_reg <= 1'b1; //wait for HLDA
                                            STATE <= SI;
                                        end else if (STATE == S1) begin 
                                            STATE <= SI;
                                            
                                        end
                                        
                                        if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                        if (STATE == S4) begin
                                            //$display("Entered S4 from Channel 0");
                                            casex(MR[3:2]) 
                                                2'b10: begin
                                                    //$display("Entered read");
                                                    D_reg <= D;  //prepare read data to be sent to CPU
                                                    //CPU HAS TO READ DATA ON DATA LINE
                                                    CADDR0 <= CADDR0 + 1; //sono byte
                                                end
                                                2'b01: begin
                                                    //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                    //$display("Entered write");
                                                    D_reg <= D; //prepare output to I/O device
                                                    CADDR0 <= CADDR0 + 1; //sono byte
                                                end 
                                            endcase
                                                STATE <= S1;
                                        end
                                        end //end of if statement
                                end //end of channel 0
                                2'b01:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale 
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from Channel 1");*/end //Special SI state --> after S0

                                            if (STATE == S1 && ADSTB == 1'b0) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (DREQ1 == 1'b0) begin
                                                                CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg <= 1'b0;
                                                                EOP_reg <= 1'b0; //interrupt fine processo
                                                                SR[5] <= 1'b0;  //disable channel 1
                                                                SR[1] <= 1'b1; //conteggio terminato per channel 1
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                if (CADDR1[7:4] == 4'hF || CADDR1[7:4] == 4'h0) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                                STATE <= S2;
                                                            end
                                                            
                                                        end 
                                                        else begin 
                                                        STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 1");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered S3 from Channel 1");


                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR1; //invio indirizzo

                                                    if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                        ADSTB_reg <= 0;
                                                    end


                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 1 entered S0, it will enter SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI; 
                                            end else if (STATE == S1) begin 
                                                STATE = SI;
                                                
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin  AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 1");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CADDR1 <= CADDR1 + 1; //sono byte
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CADDR1 <= CADDR1 + 1; //sono byte
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                            end


                                            end //end of if statement
                                    end //end of channel 1
                                2'b10:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] = MR[7:6]; TEMP[5:4] = MR[1:0];  //blocco su un canale   --->  Trovare un modo per disinserire il blocco
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from Channel 2");*/end //Special SI state --> after S0

                                            if (STATE == S1 && ADSTB == 1'b0) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (DREQ2 == 1'b0) begin
                                                                CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg <= 1'b0;
                                                                EOP_reg <= 1'b0; //interrupt fine processo
                                                                SR[6] <= 1'b0;  //disable channel 2
                                                                SR[2] <= 1'b1; //conteggio terminato per channel 2
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                if (CADDR2[7:4] == 4'hF || CADDR2[7:4] == 4'h0) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                                STATE <= S2;
                                                            end                                                            
                                                        end 
                                                        else begin 
                                                        STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 2");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered S3 from Channel S2");


                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR2; //invio indirizzo

                                                    if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                        ADSTB_reg <= 0;
                                                    end

                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 2 entered S0, will enter SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI; //original: S0
                                            end else if (STATE == S1) begin 
                                                STATE <= SI;
                                                
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 2");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CADDR2 <= CADDR2 + 1; //sono byte
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CADDR2 <= CADDR2 + 1; //sono byte
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                            end

                                            end //end of if statement
                                end //end of channel 2

                                2'b11:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from Channel 3");*/ end //Special SI state --> after S0

                                            if (STATE == S1 && ADSTB == 1'b0) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (DREQ3 == 1'b0) begin
                                                                CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg <= 1'b0;
                                                                EOP_reg <= 1'b0; //interrupt fine processo
                                                                SR[7] <= 1'b0;  //disable channel 3
                                                                SR[3] <= 1'b1; //conteggio terminato per channel 3
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                if (CADDR3[7:4] == 4'hF || CADDR3[7:4] == 4'h0) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                                STATE <= S2;
                                                            end
                                                            
                                                        end 
                                                        else begin 
                                                        STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 3");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered S3 from Channel 3");


                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR3; //invio indirizzo

                                                    if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                        ADSTB_reg <= 0;
                                                    end

                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 3 entered S0, will enter SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI;
                                            end else if (STATE == S1) begin 
                                                STATE <= SI;
                                                
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 3");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CADDR3 <= CADDR3 + 1; //sono byte
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CADDR3 <= CADDR3 + 1; //sono byte
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                            end

                                            end //end of if statement
                                end //end of channel 3
                            
                    endcase


                2'b01: //single transfer mode  -->  In single transfer si esegue un unico trasferimento alla volta: per tramettere ogni singolo dato serve inviare OGNI VOLTA l'indirizzo
                    begin
                    casex(MR[1:0])
                        2'b00: 
                        begin
                            if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                    //$display("Currently in CHANNEL 0, state: %d  at time:  %d", STATE, $time);  //  --> Per DEBUG
                                    if (HLDA == 1'b1) begin 
                                        //$display("HLDA is active");
                                        //modalità operativa del DMAC (active state)
                                        if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from CHANNEL 0");*/ end //Special SI state --> after S0

                                        if (STATE == S1) begin
                                                    if (HRQ_reg == 1) begin 
                                                        STATE <= S2;
                                                    end
                                                    else begin 
                                                        STATE <= SI;
                                                    end
                                        end

                                        if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin
                                            if (STATE == S2) begin /*$display("Entered S2 from Channel 0");*/ STATE <= S3; end else if (STATE == S3) begin
                                                //$display("Entered S3 from Channel 0:");


                                                IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                AEN_reg <= 1; //enable D to send address
                                                {D_reg, A74_reg, A30_reg} <= CADDR0; //invio indirizzo
                                            end
                                        end
                                    end
                                    else if (STATE == S0) begin 
                                        //$display("Channel 0 in S0, will update state to SI");
                                        HRQ_reg <= 1'b1; //wait for HLDA
                                        STATE <= SI;
                                    end else if (STATE == S1) begin 
                                            STATE <= SI;
                                            if (CWC0 == 16'h0000) begin
                                                        //$display("CWC0 = 0");
                                                        CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                        HRQ_reg <= 1'b0;
                                                        EOP_reg <= 1'b0; //interrupt fine processo
                                                        SR[4] <= 1'b0;  //disable channel 0
                                                        SR[0] <= 1'b1; //conteggio terminato per channel 0
                                                                        //STATE will be set to S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                    end
                                    end
                                        
                                        if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                        if (STATE == S4) begin
                                            //$display("Canale 0 entrato in S4");
                                            casex(MR[3:2]) 
                                                2'b10: begin
                                                    //$display("Entered read");
                                                    D_reg <= D;  //prepare read data to be sent to CPU
                                                    //CPU HAS TO READ DATA ON DATA LINE (SENT BY DMAC)
                                                    CWC0 <= CWC0 - 1;
                                                end
                                                2'b01: begin
                                                    //$display("Entered write");
                                                    D_reg <= D; //prepare output to I/O device
                                                    //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                    CWC0 <= CWC0 - 1;
                                                end 
                                            endcase
                                                STATE <= S1;
                                                HRQ_reg <= 1'b0;
                                        end
                            end //end of if statement
                        end //end of channel 0

                        
                        2'b01:
                            begin
                            //$display("Currently in CHANNEL 1, state: %d  at time:  %d", STATE, $time);  //  --> Per DEBUG
                            if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                    if (HLDA == 1'b1) begin 
                                        //modalità operativa del DMAC (active state)
                                        if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from CHANNEL 1");*/ end //Special SI state --> after S0

                                        if (STATE == S1) begin
                                                    if (HRQ_reg == 1) begin 
                                                        STATE <= S2;
                                                    end
                                                    else begin 
                                                        STATE <= SI;
                                                    end
                                        end

                                        if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin
                                            if (STATE == S2) begin /*$display("Entered S2 from Channel 1");*/ STATE <= S3; end else if (STATE == S3) begin 
                                                //$display("Entered S3 from Channel 1");


                                                IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                AEN_reg <= 1; //enable D to send address
                                                {D_reg, A74_reg, A30_reg} <= CADDR1; //invio indirizzo
                                            end
                                        end
                                        end
                                        else if (STATE == S0) begin 
                                            //$display("Channel 1 entered S0, will enter state SI");
                                            HRQ_reg <= 1'b1; //wait for HLDA
                                            STATE <= SI;
                                        end else if (STATE == S1) begin 
                                            STATE <= SI;
                                            if (CWC1 == 0) begin
                                                        //$display("CWC1 = 0");
                                                        CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                        HRQ_reg <= 1'b0;
                                                        EOP_reg <= 1'b0; //interrupt fine processo
                                                        SR[5] <= 1'b0;
                                                        SR[1] <= 1'b1; //conteggio terminato per channel 1
                                                                        //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                    end
                                        end
                                        
                                        if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                        if (STATE == S4) begin
                                            //$display("Entered S4 from Channel 1");
                                            casex(MR[3:2]) 
                                                2'b10: begin
                                                    //$display("Entered read");
                                                    D_reg <= D;  //prepare read data to be sent to CPU
                                                    //CPU HAS TO READ DATA ON DATA LINE
                                                    CWC1 <= CWC1 - 1;
                                                end
                                                2'b01: begin
                                                    //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                    //$display("Entered write");
                                                    D_reg <= D; //prepare output to I/O device
                                                    CWC1 <= CWC1 - 1;
                                                end 
                                            endcase
                                                STATE <= S1;
                                                HRQ_reg <= 0;
                                        end

                                        end //end of if statement
                                end //end of channel 1


                            2'b10:
                            begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale  
                                        //$display("Currently in CHANNEL 2, state: %d  at time:  %d", STATE, $time);
                                        if (HLDA == 1'b1) begin 
                                            //$display("HLDA is active");
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from CHANNEL 2");*/end //Special SI state --> after S0

                                            if (STATE == S1) begin
                                                        if (HRQ_reg == 1) begin 
                                                            STATE <= S2;
                                                        end
                                                        else begin 
                                                            STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 2");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered S3 from Channel 2");

                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR0; //invio indirizzo

                                                end
                                            end
                                        end
                                        else if (STATE == S0) begin 
                                            //$display("Channel 2 in S0");
                                            HRQ_reg <= 1'b1; //wait for HLDA
                                            STATE <= SI; 
                                            //$display("Aggiornato a SI");
                                        end else if (STATE == S1) begin 
                                                STATE <= SI;
                                                if (CWC2 == 16'h0000) begin
                                                            //$display("CWC = 0");
                                                            CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                            HRQ_reg <= 1'b0;
                                                            EOP_reg <= 1'b0; //interrupt fine processo
                                                            SR[6] <= 1'b0;  //disable channel 2
                                                            SR[2] <= 1'b1; //conteggio terminato per channel 2
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                        end
                                        end
                                                
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entrato in S4 from Channel 2");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CWC2 <= CWC2 - 1;
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CWC2 <= CWC2 - 1;
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                                    HRQ_reg <= 1'b0;
                                            end

                                end //end of if statement
                            end //end of channel 2

                            2'b11:
                            begin
                                //$display("Currently in CHANNEL 3, state: %d  at time:  %d", STATE, $time);  //  --> Per DEBUG
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale 
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from CHANNEL 3");*/ end //Special SI state --> after S0

                                            if (STATE == S1) begin
                                                    if (HRQ_reg == 1) begin 
                                                        STATE <= S2;
                                                    end
                                                    else begin 
                                                        STATE <= SI;
                                                    end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered in S2 from Channel 3");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered in S3 from Channel 3:");

                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR3; //invio indirizzo
                                                end
                                            end
                                        end
                                        else if (STATE == S0) begin 
                                            //$display("Channel 3 entered S0, it will enter SI");
                                            HRQ_reg <= 1'b1; //wait for HLDA
                                            STATE <= SI;
                                        end else if (STATE == S1) begin 
                                            STATE <= SI;
                                            if (CWC3 == 0) begin
                                                        //$display("CWC = 0");
                                                        CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                        HRQ_reg <= 1'b0;
                                                        EOP_reg <= 1'b0; //interrupt fine processo
                                                        SR[7] <= 1'b0;  //disable channel 3
                                                        SR[3] <= 1'b1; //conteggio terminato per channel 3
                                                                        //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                    end
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered in S4 from Channel 3");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CWC3 <= CWC3 - 1;
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CWC3 <= CWC3 - 1;
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                                    HRQ_reg <= 0;
                                            end

                                            end //end of if statement
                                    end //end of channel 3
                    endcase
                    end //end of single transfer mode case*/


                2'b10: 
                begin //block tranfer mode   -->   Una solo richiesta: una volta programmati A0-A7 iniziali e poi non trasmetto più indirizzi
                    casex(MR[1:0]) //select port
                        2'b00: 
                        begin
                            if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                    if (HLDA == 1'b1) begin 
                                        //modalità operativa del DMAC (active state)
                                        if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from CHANNEL 0");*/ end //Special SI state --> after S0

                                        if (STATE == S1 && ADSTB == 1'b0) begin
                                                    if (HRQ_reg == 1) begin
                                                        if (CWC0 == 0) begin
                                                            //$display("CWC = 0");
                                                            CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                            HRQ_reg <= 1'b0;
                                                            EOP_reg <= 1'b0; //interrupt fine processo
                                                            SR[4] <= 1'b0;  //disable channel 0
                                                            SR[0] <= 1'b1; //conteggio terminato per channel 0
                                                                            //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                        end else begin
                                                            if (CADDR0[7:0] == 8'hFF || CADDR0[7:0] == 8'h00) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                            STATE <= S2;
                                                        end
                                                    end 
                                                    else begin 
                                                    STATE <= SI;
                                                    end
                                        end

                                        if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin
                                            if (STATE == S2) begin /*$display("Entered S2 from Channel 0");*/ STATE <= S3; end else if (STATE == S3) begin
                                                //$display("Entered S3 from Channel 0:");

                                                IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                AEN_reg <= 1; //enable D to send address
                                                {D_reg, A74_reg, A30_reg} <= CADDR0; //invio indirizzo

                                                if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                    ADSTB_reg <= 0;
                                                end

                                            end
                                        end
                                        end
                                        else if (STATE == S0) begin 
                                            //$display("Channel 0 entered S0, will enter SI");
                                            HRQ_reg <= 1'b1; //wait for HLDA
                                            STATE <= SI; //original: S0
                                        end else if (STATE == S1) begin 
                                            STATE <= SI;
                                        end
                                        
                                        if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                        if (STATE == S4) begin
                                            //$display("Channel 0 entered S4");
                                            casex(MR[3:2]) 
                                                2'b10: begin
                                                    //$display("Entered read");
                                                    D_reg <= D;  //prepare read data to be sent to CPU
                                                    //CPU HAS TO READ DATA ON DATA LINE
                                                    CWC0 <= CWC0 - 1;
                                                    CADDR0 <= CADDR0 + 1; //sono byte
                                                end
                                                2'b01: begin
                                                    //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                    //$display("Entered write");
                                                    D_reg <= D; //prepare output to I/O device
                                                    CWC0 <= CWC0 - 1;
                                                    CADDR0 <= CADDR0 + 1; //sono byte
                                                end 
                                            endcase
                                                STATE <= S1;
                                        end
                                        end //end of if statement
                                end //end of channel 0
                        


                                2'b01:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from CHANNEL 1");*/ end //Special SI state --> after S0

                                            if (STATE == S1 && ADSTB == 1'b0) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (CWC1 == 0) begin
                                                                //$display("CWC1 = 0");
                                                                CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg <= 1'b0;
                                                                EOP_reg <= 1'b0; //interrupt fine processo
                                                                SR[5] <= 1'b0;  //disable channel 1
                                                                SR[1] <= 1'b1; //conteggio terminato per channel 1
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                if (CADDR1[7:0] == 8'hFF || CADDR1[7:0] == 8'h00) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                                STATE <= S2;
                                                            end
                                                            
                                                        end 
                                                        else begin 
                                                        STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 1");*/ STATE <= S3; end else if (STATE == S3) begin
                                                    //$display("Entered S3 from Channel 1:");

                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR1; //invio indirizzo

                                                    if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                        ADSTB_reg <= 0;
                                                    end

                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 1 entered S0, will enter SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI;
                                            end else if (STATE == S1) begin 
                                                STATE <= SI;
                                                
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 1");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CWC1 <= CWC1 - 1;
                                                        CADDR1 <= CADDR1 + 1; //sono byte
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CWC1 <= CWC1 - 1;
                                                        CADDR1 <= CADDR1 + 1; //sono byte
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                            end

                                            end //end of if statement
                                    end //end of channel 1
                                2'b10:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] = MR[7:6]; TEMP[5:4] = MR[1:0];  //blocco su un canale
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from Channel 2");*/ end //Special SI state --> after S0

                                            if (STATE == S1 && ADSTB == 1'b0) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (CWC2 == 0) begin
                                                                //$display("CWC = 0");
                                                                CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg <= 1'b0;
                                                                EOP_reg <= 1'b0; //interrupt fine processo
                                                                SR[6] <= 1'b0;  //disable channel 2
                                                                SR[2] <= 1'b1; //conteggio terminato per channel 2
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                if (CADDR2[7:0] == 8'hFF || CADDR2[7:0] == 8'h00) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                                STATE <= S2;
                                                            end
                                                            
                                                        end 
                                                        else begin 
                                                        STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 1");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered S3 from Channel 1:");


                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR2; //invio indirizzo

                                                    if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                        ADSTB_reg <= 0;
                                                    end

                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 1 entered in S0, it will enter in SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI;
                                            end else if (STATE == S1) begin 
                                                STATE <= SI;
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 1");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CWC2 <= CWC2 - 1;
                                                        CADDR2 <= CADDR2 + 1; //sono byte
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CWC2 <= CWC2 - 1;
                                                        CADDR2 <= CADDR2 + 1; //sono byte
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                            end
                                            end //end of if statement
                                    end //end of channel 2

                                2'b11:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] <= MR[7:6]; TEMP[5:4] <= MR[1:0];  //blocco su un canale
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE <= S1; /*$display("Entered S1 from Channel 3");*/end //Special SI state --> after S0

                                            if (STATE == S1 && ADSTB == 1'b0) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (CWC3 == 0) begin
                                                                //$display("CWC = 0");
                                                                CHANNEL_LOCK <= 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg <= 1'b0;
                                                                EOP_reg <= 1'b0; //interrupt fine processo
                                                                SR[7] <= 1'b0;  //disable channel 3
                                                                SR[3] <= 1'b1; //conteggio terminato per channel 3
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                if (CADDR3[7:0] == 8'hFF || CADDR3[7:0] == 8'h00) ADSTB_reg <= 1; //invia sul latch esterno D7-D0
                                                                STATE <= S2;
                                                            end
                                                            
                                                        end 
                                                        else begin 
                                                        STATE <= SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 3");*/ STATE <= S3; end else if (STATE == S3) begin  
                                                    //$display("Entered S3 from Channel 3:");


                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 

                                                    AEN_reg <= 1; //enable D to send address
                                                    {D_reg, A74_reg, A30_reg} <= CADDR3; //invio indirizzo

                                                    if (ADSTB == 1'b1) begin  //se ADSTB == 1
                                                        ADSTB_reg <= 0;
                                                    end
                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 3 entered S0, it will enter SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI; //original: S0
                                            end else if (STATE == S1) begin 
                                                STATE <= SI;
                                                
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin AEN_reg <= 1'b0;  STATE <= S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 3");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CWC3 <= CWC3 - 1;
                                                        CADDR3 <= CADDR3 + 1; //sono byte
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CWC3 <= CWC3 - 1;
                                                        CADDR3 <= CADDR3 + 1; //sono byte
                                                    end 
                                                endcase
                                                    STATE <= S1;
                                            end


                                            end //end of if statement
                                    end //end of channel 3
                    endcase
                end //end of block transfer mode

                2'b11: begin /*cascade mode*/ 
                    casex(MR[1:0]) //select port
                        2'b00: 
                        begin
                            if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] = MR[7:6]; TEMP[5:4] = MR[1:0];  //blocco su un canale 
                                    if (HLDA == 1'b1) begin 
                                        //modalità operativa del DMAC (active state)
                                        if (STATE == SI) begin STATE = S1; /*$display("Entra in S1 da CANALE 0");*/ end //Special SI state --> after S0

                                        if (STATE == S1) begin
                                                    if (HRQ_reg == 1) begin
                                                        if (CWC0 == 0) begin
                                                            //$display("CWC = 0");
                                                            CHANNEL_LOCK = 1'b0; //unlock channel at End of Transfer
                                                            HRQ_reg = 1'b0;
                                                            EOP_reg = 1'b0; //interrupt fine processo
                                                            SR[4] <= 1'b0;  //disable channel 0
                                                            SR[0] = 1'b1; //conteggio terminato per channel 0
                                                                            //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                        end else begin
                                                            STATE = S2;
                                                        end
                                                        
                                                    end 
                                                    else begin 
                                                    STATE = SI;
                                                    end
                                        end

                                        if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                            if (STATE == S2) begin /*$display("Entered S2 from Channel 0");*/ STATE = S3; end else if (STATE == S3) begin 
                                                //$display("Entered S3 from Channel 0:");

                                                IOW_MEMW_reg[1:0] <= IOW_MEMW_; 
                                            end
                                        end
                                        end
                                        else if (STATE == S0) begin 
                                            //$display("Channel 0 entered S0, it will enter SI");
                                            HRQ_reg <= 1'b1; //wait for HLDA
                                            STATE <= SI;
                                        end else if (STATE == S1) begin 
                                            STATE = SI;
                                            
                                        end
                                        
                                        if (READY == 1'b0 && STATE == S3) begin STATE = S4; end

                                        if (STATE == S4) begin
                                            //$display("Entered S4 from Channel 0");
                                            casex(MR[3:2]) 
                                                2'b10: begin
                                                    //$display("Entered read");
                                                    D_reg <= D;  //prepare read data to be sent to CPU
                                                    //CPU HAS TO READ DATA ON DATA LINE
                                                    CWC0 <= CWC0 - 1;
                                                end
                                                2'b01: begin
                                                    //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                    //$display("Entered write");
                                                    D_reg <= D; //prepare output to I/O device
                                                    CWC0 <= CWC0 - 1;
                                                end 
                                            endcase
                                                STATE = S1;
                                        end

                                        end //end of if statement
                                end //end of channel 0
                                                
                                2'b01:
                                    begin
                                    if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] = MR[7:6]; TEMP[5:4] = MR[1:0];  //blocco su un canale
                                            if (HLDA == 1'b1) begin 
                                                //modalità operativa del DMAC (active state)
                                                if (STATE == SI) begin STATE = S1; /*$display("Entra in S1 da CANALE 1");*/ end //Special SI state --> after S0

                                                if (STATE == S1) begin
                                                            if (HRQ_reg == 1) begin
                                                                if (CWC1 == 0) begin
                                                                    //$display("CWC = 0");
                                                                    CHANNEL_LOCK = 1'b0; //unlock channel at End of Transfer
                                                                    HRQ_reg = 1'b0;
                                                                    EOP_reg = 1'b0; //interrupt fine processo
                                                                    SR[5] <= 1'b0;  //disable channel 1
                                                                    SR[1] = 1'b1; //conteggio terminato per channel 1
                                                                                    //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                                end else begin
                                                                    STATE = S2;
                                                                end
                                                                
                                                            end 
                                                            else begin 
                                                                STATE = SI;
                                                            end
                                                end

                                                if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin //if READY == 1 && STATE != S4
                                                    if (STATE == S2) begin /*$display("Entered S2 from Channel 1");*/ STATE = S3; end else if (STATE == S3) begin
                                                        //$display("Entered S3 from Channel 1:");

                                                        IOW_MEMW_reg[1:0] <= IOW_MEMW_; 
                                                    end
                                                end
                                                end
                                                else if (STATE == S0) begin 
                                                    //$display("Channel 1 entered S0, will enter SI");
                                                    HRQ_reg <= 1'b1; //wait for HLDA
                                                    STATE <= SI; //original: S0
                                                end else if (STATE == S1) begin 
                                                    STATE = SI;
                                                    
                                                end
                                                
                                                if (READY == 1'b0 && STATE == S3) begin STATE = S4; end

                                                if (STATE == S4) begin
                                                    //$display("Entered S4 from Channel 1");
                                                    casex(MR[3:2]) 
                                                        2'b10: begin
                                                            //$display("Entered read");
                                                            D_reg <= D;  //prepare read data to be sent to CPU
                                                            //CPU HAS TO READ DATA ON DATA LINE
                                                            CWC1 <= CWC1 - 1;
                                                        end
                                                        2'b01: begin
                                                            //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                            //$display("Entered write");
                                                            D_reg <= D; //prepare output to I/O device
                                                            CWC1 <= CWC1 - 1;
                                                        end 
                                                    endcase
                                                        STATE = S1;
                                                end
                                    end //end of if statement
                                end //end of channel 1
                                2'b10:
                                begin
                                    if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] = MR[7:6]; TEMP[5:4] = MR[1:0];  //blocco su un canale  
                                            if (HLDA == 1'b1) begin 
                                                //modalità operativa del DMAC (active state)
                                                if (STATE == SI) begin STATE = S1; /*$display("Entered S1 from CHANNEL 2");*/ end //Special SI state --> after S0

                                                if (STATE == S1) begin
                                                            if (HRQ_reg == 1) begin
                                                                if (CWC2 == 0) begin
                                                                    //$display("CWC = 0");
                                                                    CHANNEL_LOCK = 1'b0; //unlock channel at End of Transfer
                                                                    HRQ_reg = 1'b0;
                                                                    EOP_reg = 1'b0; //interrupt fine processo
                                                                    SR[6] <= 1'b0;  //disable channel 2
                                                                    SR[2] = 1'b1; //conteggio terminato per channel 2
                                                                                    //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                                end else begin
                                                                    STATE = S2;
                                                                end
                                                                
                                                            end 
                                                            else begin 
                                                            STATE = SI;
                                                            end
                                                end

                                                if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin
                                                    if (STATE == S2) begin /*$display("Entered S2 from Channel 2");*/ STATE = S3; end else if (STATE == S3) begin 
                                                        //$display("Entered S3 from Channel 2");

                                                        IOW_MEMW_reg[1:0] <= IOW_MEMW_; 
                                                    end
                                                end
                                                end
                                                else if (STATE == S0) begin 
                                                    //$display("Channel 2 entred S0, it will enter SI");
                                                    HRQ_reg <= 1'b1; //wait for HLDA
                                                    STATE <= SI; 
                                                end else if (STATE == S1) begin 
                                                    STATE = SI;
                                                end
                                                
                                                if (READY == 1'b0 && STATE == S3) begin STATE = S4; end

                                                if (STATE == S4) begin
                                                    //$display("Entered S4 from Channel 2");
                                                    casex(MR[3:2]) 
                                                        2'b10: begin
                                                            //$display("Entered read");
                                                            D_reg <= D;  //prepare read data to be sent to CPU
                                                            //CPU HAS TO READ DATA ON DATA LINE
                                                            CWC2 <= CWC2 - 1;
                                                        end
                                                        2'b01: begin
                                                            //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                            //$display("Entered write");
                                                            D_reg <= D; //prepare output to I/O device
                                                            CWC2 <= CWC2 - 1;
                                                        end 
                                                    endcase
                                                        STATE = S1;
                                                end


                                    end //end of if statement
                                end //end of channel 2
                                2'b11:
                                begin
                                if (CHANNEL_LOCK == 1'b1) begin TEMP[7:6] = MR[7:6]; TEMP[5:4] = MR[1:0];  //blocco su un canale
                                        if (HLDA == 1'b1) begin 
                                            //modalità operativa del DMAC (active state)
                                            if (STATE == SI) begin STATE = S1; /*$display("Entered S1 from CHANNEL 3");*/ end //Special SI state --> after S0

                                            if (STATE == S1) begin
                                                        if (HRQ_reg == 1) begin
                                                            if (CWC3 == 0) begin
                                                                //$display("CWC = 0");
                                                                CHANNEL_LOCK = 1'b0; //unlock channel at End of Transfer
                                                                HRQ_reg = 1'b0;
                                                                EOP_reg = 1'b0; //interrupt fine processo
                                                                SR[7] <= 1'b0;  //disable channel 3
                                                                SR[3] = 1'b1; //conteggio terminato per channel 3
                                                                                //STATE will be set S4 in EOP_ evaluation as PROCESS IS OVER!!!!
                                                            end else begin
                                                                STATE = S2;
                                                            end
                                                            
                                                        end 
                                                        else begin 
                                                        STATE = SI;
                                                        end
                                            end

                                            if (READY == 1'b1 && (STATE == S2 || STATE == S3)) begin 
                                                if (STATE == S2) begin /*$display("Entered S2 from Channel 3");*/ STATE = S3; end else if (STATE == S3) begin 
                                                    //$display("Entered S3 from Channel 3");

                                                    IOW_MEMW_reg[1:0] <= IOW_MEMW_; 
                                                end
                                            end
                                            end
                                            else if (STATE == S0) begin 
                                                //$display("Channel 3 entered S0, it will enter SI");
                                                HRQ_reg <= 1'b1; //wait for HLDA
                                                STATE <= SI; //original: S0
                                            end else if (STATE == S1) begin 
                                                STATE = SI;
                                                
                                            end
                                            
                                            if (READY == 1'b0 && STATE == S3) begin STATE = S4; end

                                            if (STATE == S4) begin
                                                //$display("Entered S4 from Channel 3");
                                                casex(MR[3:2]) 
                                                    2'b10: begin
                                                        //$display("Entered read");
                                                        D_reg <= D;  //prepare read data to be sent to CPU
                                                        //CPU HAS TO READ DATA ON DATA LINE
                                                        CWC3 <= CWC3 - 1;
                                                    end
                                                    2'b01: begin
                                                        //DATA MUST BE AVAILABLE ON DATA LINE to be sent to I/O device
                                                        //$display("Entered write");
                                                        D_reg <= D; //prepare output to I/O device
                                                        CWC3 <= CWC3 - 1;
                                                    end 
                                                endcase
                                                    STATE = S1;
                                            end


                                            end //end of if statement
                                end //end of channel 3
                    endcase
                end //end of cascade mode
            endcase //end transfer mode case
    
    end //end active cycle operations
    end //end of active cycle


Priority_Enc Priority_Encoder(DREQ_wire, HLDA, CR, MKR[3:0], USAGE, HRQ, DACK_wire, SERVED_CHANNEL, CLK, RESET);

endmodule //end of Intel_8237A

/*
##################
#PRIORITY ENCODER#
##################
*/

module Priority_Enc(DREQ, HLDA, COMMAND, MASK,    USG,    HRQ, DACK,    SERVED_CHANNEL,  CLK, RESET);

    input[3:0] DREQ;
    input HLDA;
    input[7:0] COMMAND;
    input[3:0] MASK;


    input HRQ;
    output[3:0] DACK;
    reg[3:0] DACK_reg;
    assign DACK = DACK_reg;

    input CLK;
    input RESET;

    input[7:0] USG;

    reg[1:0] SERVED_CHANNEL_REG;

    output[1:0] SERVED_CHANNEL;
    assign SERVED_CHANNEL = SERVED_CHANNEL_REG;


    always @(negedge CLK) begin
        casex(COMMAND[4]) //valuta il bit 4 di CR --> priority
            1'b0: //fixed priority  -->  Valuta canale 0, poi canale 1, poi canale 2, poi canale 3
            begin
                SERVED_CHANNEL_REG <= (DREQ[0] == 1'b1 && MASK[0] == 1'b1) ? 2'b00 :
                                (DREQ[1] == 1'b1 && MASK[1] == 1'b1) ? 2'b01 :
                                (DREQ[2] == 1'b1 && MASK[2] == 1'b1) ? 2'b10 :
                                (DREQ[3] == 1'b1 && MASK[3] == 1'b1) ? 2'b11 : 2'bxx;
                DACK_reg[SERVED_CHANNEL_REG] <= 1'b1;
                if (DREQ[0] == 0) DACK_reg[0] <= 0;
                if (DREQ[1] == 0) DACK_reg[1] <= 0;
                if (DREQ[2] == 0) DACK_reg[2] <= 0;
                if (DREQ[3] == 0) DACK_reg[3] <= 0;
            end


            1'b1: //rotating priority --> last used will be updated to LOWEST priority
            begin
                SERVED_CHANNEL_REG <= (USG[1:0] == 0 && MASK[0] == 1 && DREQ[0] == 1'b1) ? 2'b00 :
                                            (USG[3:2] == 0 && MASK[1] == 1 && DREQ[1] == 1'b1) ? 2'b01 :
                                            (USG[5:4] == 0 && MASK[2] == 1 && DREQ[2] == 1'b1) ? 2'b10 :
                                            (USG[7:6] == 0 && MASK[3] == 1 && DREQ[3] == 1'b1) ? 2'b11 : 2'bxx;
                DACK_reg[SERVED_CHANNEL_REG] <= 1'b1;
                if (DREQ[0] == 0) DACK_reg[0] <= 0;
                if (DREQ[1] == 0) DACK_reg[1] <= 0;
                if (DREQ[2] == 0) DACK_reg[2] <= 0;
                if (DREQ[3] == 0) DACK_reg[3] <= 0;
            end



        endcase

    end

endmodule

module TestBench;

    reg clock;
    reg reset;

    //registers to program DMAC
    
    //inputs (for DMA)
    reg HLDA;
    reg READY;
    reg[3:0] DREQ30;


    //inout and 'output enable' registers (for DMA)  --> tri-state buffers are needed for inout ports
    wire[3:0] A30;
    reg A30_oe;
    assign A30 = (!A30_oe) ? A30_w : 4'hz;


    wire[7:0] D;
    wire[7:0] D2;
    reg D_oe; //oe da DMA a CPU (e scrittura da CPU a DMA se '0')
    reg D_oe2; //oe da DMA a periferica (e scrittura da periferca a DMA se '0')
    assign D = (!D_oe2) ? D_w2 : (!D_oe) ? D_w : 8'hzz;

    
    wire EOP_;
    reg EOP_oe;
    assign EOP_ = (!EOP_oe) ? EOP_w : 1'bz;


    wire[1:0] IOR_MEMR_;
    reg IOR_MEMR_oe;
    assign IOR_MEMR_ = (!IOR_MEMR_oe) ? IOR_MEMR_w : 2'bzz;

    
    wire[1:0] IOW_MEMW_;
    reg IOW_MEMW_oe;
    assign IOW_MEMW_ = (!IOW_MEMW_oe) ? IOW_MEMW_w : 2'bzz;


    //inout registers 
    reg[3:0] A30_w; //write
    reg[3:0] A30_r; //read


    reg[7:0] D_w;
    reg[7:0] D_w2;
    reg[7:0] D_r;


    reg EOP_w;
    reg EOP_r;


    reg[1:0] IOR_MEMR_w;
    reg[1:0] IOR_MEMR_r;


    reg[1:0] IOW_MEMW_w;
    reg[1:0] IOW_MEMW_r;

    reg HRQ_r;

    always @(posedge clock) begin 
        A30_r <= A30;

        D_r <= D_w;

        EOP_r <= EOP_w;

        IOR_MEMR_r <= IOR_MEMR_w;

        IOW_MEMW_r <= IOW_MEMW_w;

        HRQ_r <= HRQ;
    end


    //out (for DMA)
    wire HRQ;
    wire[3:0] A74;
    wire ADSTB;
    wire AEN;
    wire[3:0] DACK30;

    //physical implementations
    reg CS_;
    wire[1:0] Vcc_GND;
    assign Vcc_GND = 2'b10;


    //montaggio del modulo
    Intel_8237A DMAC(A30, A30_oe, D, D_oe, HLDA, EOP_, EOP_oe, reset, clock, 
    IOR_MEMR_, IOR_MEMR_oe, IOW_MEMW_, IOW_MEMW_oe, READY, DREQ30[0], DREQ30[1], DREQ30[2], DREQ30[3],
    HRQ, A74, ADSTB, AEN, DACK30[0], DACK30[1], DACK30[2], DACK30[3],
    CS_, Vcc_GND);

    reg[15:0] received_address;
    reg[7:0] received_data;


    initial begin //must be an isolate code block due to forever loop
        clock = 1'b0;
        forever #5 begin clock <= !clock; end 
    end





    //test of single transfer, write mode, fixed priority, channel 0 and channel 1
    /*
    initial begin
        //to create wave format file
        $dumpfile("DMA_wave.vcd");
        $dumpvars;

        CS_ = 0;
        EOP_oe = 1'b1;
        HLDA = 1'b0;

        D_oe2 = 1'b1;

        #3 @(posedge clock) reset = 1'b1; 
        #8
        reset = 1'b0; //reset pulse

        //end of standard initialization


        //initial controller setup
        DREQ30[0] = 1'b1; //send request on channel 0
        IOW_MEMW_oe = 1'b0;
        IOR_MEMR_oe = 1'b0;

        IOW_MEMW_w[1] = 1'b0; 

        
        A30_oe = 1'b0;
        D_oe = 1'b0;
        @(negedge clock) A30_w = 4'h8; //write data on command register
        D_w = 8'h00; //fixed priority, NOT mem2mem
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent CR: %b  on DATA\n", D);


        @(negedge clock) A30_w = 4'hB; //write data on mode register
        D_w = 8'b01zz0100; //single transfer, write, channel 0
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MR: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'hF; //write data on mask register
        D_w = 8'h03; //enable channel 0 and channel 1
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MKR: %b  on DATA\n", D);

        

        @(negedge clock) A30_w = 4'h1; //send channel 0 word count on data line
        D_w = 8'h01; //send 1 word (LSBs)
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'h00; //MSBs
        @(D) $display("Sent word: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'h0; //write address on channel 0 via data line
        D_w = 8'hAB; //send address LSBs
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'hFF; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D);

        DREQ30[1] = 1'b1; //send request on channel 1

        
        @(negedge clock) A30_w = 4'h3; //send channel 1 word count on data line
        D_w = 8'h02; //send 1 word (LSBs)
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D_w);
        
        @(negedge clock) D_w = 8'h00; //MSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);

        @(negedge clock) A30_w = 4'h2; //write address #1 on channel 1 via data line
        D_w = 8'hCD; //send address LSBs
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D_w);
        @(negedge clock) D_w = 8'h00; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);


        @(negedge clock)

        //active cycle transfer for channel 0
        @(posedge clock) A30_oe = 1'b1;
        D_oe = 1'b1;
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        READY = 1'b0;

        @(posedge clock)
        D_oe = 1'b0; //scrivere da CPU
        D_w = 8'h18;


        //DMA riceve

        @(posedge clock)
        D_oe = 1'b1; //ricezione da DMA
        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);

        DREQ30[0] = 0;

        @(HRQ_r) HLDA = 1'b0;
        READY = 1'b0;



        //active cycle transfer for channel 1
        
        
        @(posedge clock)
        @(HRQ_r) 
        HLDA = 1'b1;

        @(negedge clock) READY = 1'b1;
        

        @(AEN)

        @(negedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        
        
        READY = 1'b0;
        D_oe = 1'b0; //scrivere da CPU
        D_w = 8'h20;

        //invio a DMA
        
        //wait for DMA to enter S4
        @(negedge clock) 
        @(negedge clock) 

        @(posedge clock) D_oe = 1'b1; //ricevo da DMA
        received_data[7:0] = D; //receive written data
        
        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b", EOP_);

        //CPU riprende controllo della linea per invio secondo indirizzo per canale 1
        A30_oe = 1'b0;
        D_oe = 1'b0;
        HLDA = 1'b0;


        @(negedge clock) A30_w = 4'h2; //write address #1 on channel 1 via data line
        D_w = 8'hEF; //send address LSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);
        @(negedge clock) D_w = 8'h01; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);
        $display("STATO dopo stampa invio: %d", DMAC.STATE);

        
        @(negedge clock) A30_oe = 1'b1;
        D_oe = 1'b1;

 
        HLDA = 1'b0;

        @(posedge clock)
        HLDA = 1'b1;

        @(negedge clock) READY = 1'b1;

        @(AEN)


        @(negedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        
        READY = 1'b0;
        D_oe = 1'b0; //scrivere da CPU
        D_w = 8'hAF;
        
        //wait for DMA to enter S4
        @(negedge clock)
        @(negedge clock)

        //invio a DMA

        @(posedge clock) D_oe = 1'b1; //ricevo da DMA
        received_data[7:0] = D; //receive written data
        
        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b", EOP_);

        @(posedge clock) HLDA = 1'b0; /////AGGIUNTO PER INTERRUPT FINALE

        #100;

        $finish;
    end
    */


    //test of single transfer, write mode, rotating priority, channel 0 and channel 1  (same as before, but with Rotating Priority)
    /*
    initial begin
        //to create wave format file
        $dumpfile("DMA_wave.vcd");
        $dumpvars;

        CS_ = 0;
        EOP_oe = 1'b1;
        HLDA = 1'b0;

        D_oe2 = 1'b1;

        #3 @(posedge clock) reset = 1'b1; 
        #8
        reset = 1'b0; //reset pulse

        //end of standard initialization


        //initial controller setup
        DREQ30[0] = 1'b1; //send request on channel 0
        IOW_MEMW_oe = 1'b0;
        IOR_MEMR_oe = 1'b0;

        IOW_MEMW_w[1] = 1'b0; 

        
        A30_oe = 1'b0;
        D_oe = 1'b0;
        @(negedge clock) A30_w = 4'h8; //write data on command register
        D_w = 8'h10; //rotating priority, NOT mem2mem
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent CR: %b  on DATA\n", D);


        @(negedge clock) A30_w = 4'hB; //write data on mode register
        D_w = 8'b01zz0100; //single transfer, write, channel 0
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MR: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'hF; //write data on mask register
        D_w = 8'h03; //enable channel 0 and channel 1
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MKR: %b  on DATA\n", D);

        

        @(negedge clock) A30_w = 4'h1; //send channel 0 word count on data line
        D_w = 8'h01; //send 1 word (LSBs)
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'h00; //MSBs
        @(D) $display("Sent word: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'h0; //write address on channel 0 via data line
        D_w = 8'hAB; //send address LSBs
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'hFF; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D);



        DREQ30[1] = 1'b1; //send request on channel 1

        
        @(negedge clock) A30_w = 4'h3; //send channel 1 word count on data line
        D_w = 8'h02; //send 1 word (LSBs)
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D_w);
        
        @(negedge clock) D_w = 8'h00; //MSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);

        @(negedge clock) A30_w = 4'h2; //write address #1 on channel 1 via data line
        D_w = 8'hCD; //send address LSBs
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D_w);
        @(negedge clock) D_w = 8'h00; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);


        @(negedge clock)

        //active cycle transfer for channel 0
        @(posedge clock) A30_oe = 1'b1;
        D_oe = 1'b1;
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        READY = 1'b0;

        @(posedge clock)
        D_oe = 1'b0; //scrivere da CPU
        D_w = 8'h18;



        @(posedge clock)
        D_oe = 1'b1; //ricevo da DMA
        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);

        DREQ30[0] = 0;

        @(HRQ_r) HLDA <= 1'b0;
        READY <= 1'b0;



        //active cycle transfer for channel 1
        
        
        @(posedge clock)
        @(HRQ_r) 
        HLDA = 1'b1;


        @(negedge clock) READY = 1'b1;
        

        @(AEN)

        @(negedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        
        
        READY = 1'b0;
        D_oe = 1'b0; //scrivere da CPU
        D_w = 8'h20;

        //invio a DMA
    
        //wait for DMA to enter S4
        @(negedge clock)
        @(negedge clock)

        @(posedge clock) D_oe = 1'b1; //ricevo da DMA
        received_data[7:0] = D; //receive written data
        
        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b", EOP_);



        //CPU riprende controllo della linea per invio secondo indirizzo per canale 1
        A30_oe = 1'b0;
        D_oe = 1'b0;
        HLDA = 1'b0;

        //@(posedge clock)

        @(negedge clock) A30_w = 4'h2; //write address #1 on channel 1 via data line
        D_w = 8'hEF; //send address LSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);
        @(negedge clock) D_w = 8'h01; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D_w);
        $display("STATO dopo stampa invio: %d", DMAC.STATE);

        @(negedge clock) A30_oe = 1'b1;
        D_oe = 1'b1;

        HLDA = 1'b0;

        @(posedge clock)
        HLDA = 1'b1;

        @(negedge clock) READY = 1'b1;

        @(AEN)

        @(negedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        
        READY = 1'b0;
        D_oe = 1'b0; //scrivere da CPU
        D_w = 8'hAF;

        //invio a DMA

        //wait for DMA to enter S4
        @(negedge clock)
        @(negedge clock)

        @(posedge clock) D_oe = 1'b1; //ricevo da DMA
        received_data[7:0] = D; //receive written data
        
        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b", EOP_);


        $finish;
    end*/




    
    //test block transfer
    /*
    initial begin
        //to create wave format file
        $dumpfile("DMA_wave.vcd");
        $dumpvars;

        CS_ = 0;
        EOP_oe = 1'b1;
        HLDA = 1'b0;

        D_oe2 = 1'b1;

        #3 @(posedge clock) reset = 1'b1; 
        #8
        reset = 1'b0; //reset pulse

        //end of standard initialization


        //initial controller setup
        DREQ30[0] = 1'b1; //send request on channel 0
        IOW_MEMW_oe = 1'b0;
        IOR_MEMR_oe = 1'b0;

        IOW_MEMW_w[1] = 1'b0; 

        
        A30_oe = 1'b0;
        D_oe = 1'b0;
        @(negedge clock) A30_w = 4'h8; //write data on command register
        D_w = 8'h00; //fixed priority, NOT mem2mem
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent CR: %b  on DATA\n", D);


        @(negedge clock) A30_w = 4'hB; //write data on mode register
        D_w = 8'b10zz1000; //block transfer, read, channel 0
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MR: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'hF; //write data on mask register
        D_w = 8'h01; //enable channel 0
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MKR: %b  on DATA\n", D);


        @(negedge clock) A30_w = 4'h1; //send channel 0 word count on data line
        D_w = 8'h03; //send 3 word (LSBs)
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'h00; //MSBs
        @(D) $display("Sent word: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'h0; //write address on channel 0 via data line
        D_w = 8'h00; //send address LSBs
        $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'hFF; //send address MSBs
        @(D) $display("Sent word: %b  on DATA\n", D);


        @(negedge clock)

        //active cycle transfer for channel 0
        @(posedge clock) A30_oe = 1'b1;
        D_oe = 1'b1;
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        
        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        READY = 1'b0;

        @(posedge clock)
        //ricevo  da DMA i dati inviati da I/O device
        D_oe = 1'b0;
        D_oe2 = 1'b0;//Scrivere da CPU
        D_w2 = 8'h80;

        //DMA riceve

        @(posedge clock)
        D_oe2 = 1'b1; //invio da DMA a CPU    (D_oe == 1 --->  DMA invia dato)
        D_oe = 1'b1;

        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);


        //TRASFERIMENTO 2

        @(negedge clock)

        //active cycle transfer for channel 0
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        $display("Inviato indirizzo a tempo: %t", $time);
        READY = 1'b0;

        @(posedge clock)
        $display("Invio dati");
        //ricevo  da DMA i dati inviati da I/O device
        D_oe = 1'b0;
        D_oe2 = 1'b0;//Scrivere da CPU
        D_w2 = 8'h81;
        //DMA riceve

        @(posedge clock)
        D_oe2 = 1'b1;
        D_oe = 1'b1; //invio da DMA a CPU


        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);


        //TRASFERIMENTO 3

        @(negedge clock)

        //active cycle transfer for channel 0
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        READY = 1'b0;

        @(posedge clock)
        //ricevo  da DMA i dati inviati da I/O device
        D_oe = 1'b0;
        D_oe2 = 1'b0;//Scrivere da CPU
        D_w2 = 8'h82;


        //DMA riceve

        @(posedge clock)
        //invio da DMA a CPU
        D_oe2 = 1'b1;
        D_oe = 1'b1;

        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);

        #100;

        $finish;
    end*/


    //test demand mode, channel 0, read
    /*
    initial begin
        //to create wave format file
        $dumpfile("DMA_wave.vcd");
        $dumpvars;

        CS_ = 0;
        EOP_oe = 1'b1;
        HLDA = 1'b0;

        D_oe2 = 1'b1;

        #3 @(posedge clock) reset = 1'b1; 
        #8
        reset = 1'b0; //reset pulse

        //end of standard initialization


        //initial controller setup
        DREQ30[0] = 1'b1; //send request on channel 0
        IOW_MEMW_oe = 1'b0;
        IOR_MEMR_oe = 1'b0;

        IOW_MEMW_w[1] = 1'b0; 

        
        A30_oe = 1'b0;
        D_oe = 1'b0;
        @(negedge clock) A30_w = 4'h8; //write data on command register
        D_w = 8'h00; //fixed priority, NOT mem2mem
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent CR: %b  on DATA\n", D);


        @(negedge clock) A30_w = 4'hB; //write data on mode register
        D_w = 8'b00zz1000; //block transfer, read, channel 0
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MR: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'hF; //write data on mask register
        D_w = 8'h01; //enable channel 0
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent MKR: %b  on DATA\n", D);

        @(negedge clock) A30_w = 4'h0; //write initial address on channel 0 via data line
        D_w = 8'h00; //send address LSBs
        #3 $display("Sent word: %b  on DATA\n", D);
        @(negedge clock) D_w = 8'hFF; //send address MSBs
        @(D) $display("Sent A30: %b  \n", A30);
        $display("Sent word: %b  on DATA\n", D);


        @(negedge clock)

        //active cycle transfer for channel 0
        @(posedge clock) A30_oe = 1'b1;
        D_oe = 1'b1;
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        READY = 1'b0;

        @(posedge clock)
        //ricevo  da DMA i dati inviati da I/O device
        D_oe = 1'b0;
        D_oe2 = 1'b0;//Scrivere da CPU
        D_w2 = 8'h80;

        //DMA riceve

        @(posedge clock)
        D_oe2 = 1'b1; //invio da DMA a CPU    (D_oe == 1 --->  DMA invia dato)
        D_oe = 1'b1;

        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);


        //TRASFERIMENTO 2

        @(negedge clock)

        //active cycle transfer for channel 0
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        $display("Inviato indirizzo a tempo: %t", $time);
        READY = 1'b0;

        @(posedge clock)
        $display("Invio dati");
        //ricevo  da DMA i dati inviati da I/O device
        D_oe = 1'b0;
        D_oe2 = 1'b0;//Scrivere da CPU
        D_w2 = 8'h81;
        //DMA riceve

        @(posedge clock)
        D_oe2 = 1'b1;
        D_oe = 1'b1; //invio da DMA a CPU


        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);


        //TRASFERIMENTO 3

        @(negedge clock)

        //active cycle transfer for channel 0
        
        while (HRQ_r != 1'b1) begin #10; end
        @(posedge clock) HLDA = 1'b1;

        @(posedge clock) READY = 1'b1;
        

        @(AEN)
        @(posedge clock) received_address[15:0] = {D, A74, A30}; //receive written address
        READY = 1'b0;

        @(posedge clock)
        //ricevo  da DMA i dati inviati da I/O device
        D_oe = 1'b0;
        D_oe2 = 1'b0;//Scrivere da CPU
        D_w2 = 8'h82;


        //DMA riceve

        DREQ30[0] = 1'b0;
        @(posedge clock)
        //invio da DMA a CPU
        D_oe2 = 1'b1;
        D_oe = 1'b1;

        received_data[7:0] = D; //receive written data

        $display("RECEIVED ADDRESS: %b \nRECEIVED DATA: %b", received_address, received_data);
        $display("CURRENT EOP_: %b  at time:  %d", EOP_, $time);


        #100

        $finish;
    end*/
    
endmodule