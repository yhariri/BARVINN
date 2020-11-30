`timescale 1 ps / 1 ps

module data_transposer #(
    parameter  NUM_WORDS    =  64,   // Number of words needed before transpose 
    parameter  XLEN         =  32,   // Length of each input word
    parameter  MVU_ADDR_LEN =  32,   // MVU address length
    parameter  MVU_DATA_LEN =  32,   // MVU data length
    parameter  MAX_DATA_PREC=  16     // MAX data precision
)(
    input  logic                      clk,         // Clock
    input  logic                      rst_n,       // Asynchronous reset active low
    input  logic [31    : 0]          prec,        // Number of bits for each word
    input  logic [31    : 0]          baddr,       // Base address for writing the words
    input  logic [XLEN-1: 0]          iword,       // Base address for writing the words
    input  logic                      start,       // Start signal to indicate first word to be transposed
    output logic                      busy,        // A signal to indicate the status of the module
    output logic                      mvu_wr_en,   // MVU write enable to input RAM
    output logic [MVU_ADDR_LEN-1 : 0] mvu_wr_addr, // MVU write address to input RAM
    output logic [MVU_DATA_LEN-1 : 0] mvu_wr_word  // MVU write data to input RAM
);
    // GEN variables
    genvar i,j;

    // local buffer 
    logic     [NUM_WORDS-1 : 0] buffer[MAX_DATA_PREC-1 : 0 ];
    logic [MAX_DATA_PREC-1 : 0] prec_reg;
    // buffer counter
    localparam CNT_LEN = $clog2(NUM_WORDS);
    logic [XLEN-1 : 0 ] rd_cnt;
    logic [XLEN-1 : 0 ] wd_cnt;
    // sliced value
    logic [31:0] sliced2_val;
    logic [31:0] sliced4_val;
    logic [31:0] sliced8_val;
    logic [31:0] sliced16_val;
    logic [15:0] words2[1:0];
    logic [ 7:0] words4[3:0];
    logic [ 3:0] words8[7:0];
    logic [ 1:0] words16[15:0];

    // Local registers
    logic [XLEN-1 : 0 ] step;

    // Circuit to slice and concatenate every seconds bits from input iword into 2 vectors
    generate
        for (i = 0; i < 2; i = i + 1) begin
            for (j = 0; j < XLEN/2; j = j + 1) begin
                assign sliced2_val[i*(XLEN/2)+j] = iword[j*2+i];
            end
            assign words2[i] = sliced2_val[i*(XLEN/2) +:  (XLEN/2)];
        end
    endgenerate
    generate
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < XLEN/4; j = j + 1) begin
                assign sliced4_val[i*(XLEN/4)+j] = iword[j*4+i];
            end
            assign words4[i] = sliced4_val[i*(XLEN/4) +:  (XLEN/4)];
        end
    endgenerate
    generate
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < XLEN/8; j = j + 1) begin
                assign sliced8_val[i*(XLEN/8)+j] = iword[j*8+i];
            end
            assign words8[i] = sliced8_val[i*(XLEN/8) +:  (XLEN/8)];
        end
    endgenerate
    generate
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < XLEN/16; j = j + 1) begin
                assign sliced16_val[i*(XLEN/16)+j] = iword[j*16+i];
            end
            assign words16[i] = sliced16_val[i*(XLEN/16) +:  (XLEN/16)];
        end
    endgenerate

    function void transpose_write(int pos);
        for (int i=0; i<prec_reg; i++) begin
            if (prec_reg==2) begin
                buffer[i] = words2[i]<<(NUM_WORDS-pos-1) | buffer[i];
            end else if (prec_reg==4) begin
                buffer[i] = words4[i]<<(NUM_WORDS-pos-1) | buffer[i];
            end else if (prec_reg==8) begin
                buffer[i] = words8[i]<<(NUM_WORDS-pos-1) | buffer[i];
            end else if (prec_reg==16) begin
                buffer[i] = words16[i]<<(NUM_WORDS-pos-1) | buffer[i];
            end
        end
    endfunction

    // ASM variables
    typedef enum logic[5:0] {IDLE, DATA_READ, TRANSPOSE} trans_state_t;
    trans_state_t next_state;


    assign mvu_wr_word= buffer[wd_cnt];
    always_comb begin 
        case (prec_reg)
                  2 : step = 16;
                  4 : step =  8;
                  8 : step =  4;
                 16 : step =  2;
            default : step =  4;
        endcase
    end

    always_ff @(posedge clk) begin
        if(~rst_n) begin
            busy      <= 0;
            mvu_wr_en <= 0;
            rd_cnt    <= 0;
            wd_cnt    <= 0;
            for (int i=0; i<MAX_DATA_PREC; i++) begin
                buffer[i] = {NUM_WORDS{1'b0}};
            end
        end else begin
            case (next_state)
                IDLE : begin
                    if(start==1'b1) begin
                        next_state <= DATA_READ;
                        rd_cnt     <= 0;
                        prec_reg   <= prec[MAX_DATA_PREC-1:0];
                        mvu_wr_addr<= baddr;
                    end else begin
                        next_state <= IDLE;
                    end
                end
                DATA_READ : begin
                    if(rd_cnt >NUM_WORDS-step) begin
                        next_state <= TRANSPOSE;
                        rd_cnt     <= 0;
                        wd_cnt     <= 0;
                        mvu_wr_en  <= 1'b1;
                        busy       <= 1'b1;
                    end else begin
                        transpose_write(rd_cnt);
                        rd_cnt     <= rd_cnt  + step;
                        next_state <= DATA_READ;
                    end
                end
                TRANSPOSE: begin
                    if(wd_cnt >prec_reg) begin
                        wd_cnt     <= 0;
                        busy       <= 1'b0;
                        next_state <= IDLE;
                        mvu_wr_en  <= 1'b0;
                    end else begin
                        next_state <= TRANSPOSE;
                        wd_cnt     <= wd_cnt  + 1;
                        mvu_wr_addr<= mvu_wr_addr + 1;
                    end
                end
                default: begin
                    next_state <= IDLE;
                    wd_cnt     <= 0;
                    rd_cnt     <= 0;
                    busy       <= 0;
                end
            endcase
        end
    end
endmodule