module ch376s_module
(
  	// interface
	input       spi_clk,  // input clock
   input       cpu_clk,  // input clock
  	input       rd,
   input       wr,
  	input       reset,
   input       a0,
	
	// SPI wires
	output      sck,  // SCK
   output reg  sdcs, // SCS
	output      sdo,  // MOSI
	input       sdi,  // MISO

  	// data
   input [7:0] din,
  	output reg [7:0] dout
  
);

   wire _ready;
   wire [7:0] _dout;
   reg [7:0] _din;
   reg _wr;

   spi SPI_Master
   (
      // Control/Data Signals,
      .clk     (spi_clk),         // FPGA Clock
      .reset   (reset),
      
      // TX (MOSI) Signals
      .din     (_din),        // Byte to transmit on MOSI
      .wr      (_wr),         // Data Valid Pulse with i_TX_Byte
      
      // RX (MISO) Signals
      .dout    (_dout),       // Byte received on MISO
      
      // SPI Interface
      .sck     (sck),
      .sdi     (sdi),
      .sdo     (sdo),
      .sdcs    (_ready)       // SDCS, low at start send, high when complete
   );

   // zero when not rd
   // when a0 is 1 show status, bit 0 signals ready state.
   // when a0 is 0 show received data
   //assign dout = (rd ? (a0 ? {7'b0000000,_ready} : _dout) : 8'b00000000);

   always @(posedge cpu_clk) begin
      // hold wr and din until spi starts
      if (wr) begin
         if (a0) begin
            if (din==8'd0) begin
               // end command
               sdcs <= 1'b1;
               _wr <= 0;
            end else begin
               // start command
               sdcs <= 1'b0;
               _wr <= wr;
               _din <= din;
            end
         end else begin
            // write data
            _wr <= wr;
            _din <= din;
         end
      end
      if (rd) begin
         if (a0) begin
            // when a0 is 1 show status:
            // -bit 0 signals ready state.
            // -bit 7 signals interrupt state when CMD_SET_SD0_INT is used.
            dout <= {sdi,6'b0000000,_ready};
         end else begin
            // when a0 is 0 show received data
            dout <= _dout;
         end
      end
      // spi starts sending
      if (!_ready) begin
         _wr <= 0;
      end
   end

endmodule