module fpu_add_sub(
    input [31:0] a,            // Input operand A
    input [31:0] b,            // Input operand B
    input op,                  // Operation (0 = addition, 1 = subtraction)
    output reg [31:0] result,  // Final result
    output reg overflow,       // Overflow flag
    output reg underflow,      // Underflow flag
    output reg invalid,        // Invalid operation flag (e.g., NaNs)
    output reg inexact,        // Inexact result flag (due to rounding)
    output reg zero,           // Zero result flag
    output reg sNaN_flag,      // Signaling NaN flag
    output reg qNaN_flag       // Quiet NaN flag
); 
    // Constants
    parameter EXP_WIDTH = 8;   // Exponent width
    parameter MANT_WIDTH = 23; // Mantissa width (without hidden 1)

    // Split input numbers into sign, exponent, and mantissa
    wire sign_a = a[31];
    wire sign_b = b[31] ^ op;  // XOR with 'op' to handle subtraction
    wire [EXP_WIDTH-1:0] exp_a = a[30:23];
    wire [EXP_WIDTH-1:0] exp_b = b[30:23];
    wire [MANT_WIDTH:0] mantissa_a = {1'b1, a[22:0]}; // Implicit leading 1
    wire [MANT_WIDTH:0] mantissa_b = {1'b1, b[22:0]}; // Implicit leading 1

    // Variables
    reg [EXP_WIDTH-1:0] exp_diff;
    reg [MANT_WIDTH+2:0] mantissa_a_shifted, mantissa_b_shifted;
    reg [MANT_WIDTH+2:0] mantissa_sum;
    reg [EXP_WIDTH-1:0] exp_result;
    reg sign_result;

    // Step 1: Check for special cases (NaNs, Infinities, Zeros)
    always @(*) begin
    invalid = 0;
    sNaN_flag = 0;
    qNaN_flag = 0;
    overflow = 0;
    underflow = 0;
    zero = 0;


    // Check for NaNs in both inputs
    if ((exp_a == 8'hFF && mantissa_a[22:0] != 0) || (exp_b == 8'hFF && mantissa_b[22:0] != 0)) begin
        if (mantissa_a[22] || mantissa_b[22]) begin
            result = 32'hFFC00000;  // Negative quiet NaN
            qNaN_flag = 1;
        end else begin
            result = 32'h7FC00000;  // Positive signaling NaN
            sNaN_flag = 1;
        end
        invalid = 1;  // Set invalid flag for both NaNs
    end


        // Check for Infinities
        if ((exp_a == 8'hFF && mantissa_a[22:0] == 0) || (exp_b == 8'hFF && mantissa_b[22:0] == 0)) begin
            result = (sign_a == sign_b) ? {sign_a, 8'hFF, 23'b0} : 32'hFFC00000; // Infinity or NaN on subtraction of infinities
            invalid = (sign_a != sign_b);
        end

    // Check for signed zero result
    if (a == 32'b0 && b == 32'b0) begin
        result = {sign_a, 31'b0};  // Maintain sign of zero
        zero = 1;
    end
    
    end

    // Step 2: Calculate exponent difference and align mantissas
    always @(*) begin
        if (exp_a > exp_b) begin
            exp_diff = exp_a - exp_b;
            mantissa_a_shifted = mantissa_a;
            mantissa_b_shifted = mantissa_b >> exp_diff; // Right-shift smaller mantissa
            exp_result = exp_a;
        end else begin
            exp_diff = exp_b - exp_a;
            mantissa_a_shifted = mantissa_a >> exp_diff;
            mantissa_b_shifted = mantissa_b;
            exp_result = exp_b;
        end
    end

    // Step 3: Add or subtract mantissas
    always @(*) begin
        if (sign_a == sign_b) begin
            // Same sign, add mantissas
            mantissa_sum = mantissa_a_shifted + mantissa_b_shifted;
            sign_result = sign_a;
        end else begin
            // Different sign, subtract mantissas
            if (mantissa_a_shifted > mantissa_b_shifted) begin
                mantissa_sum = mantissa_a_shifted - mantissa_b_shifted;
                sign_result = sign_a;
            end else begin
                mantissa_sum = mantissa_b_shifted - mantissa_a_shifted;
                sign_result = sign_b;
            end
        end
    end

    // Step 4: Normalize result using LOP (Leading One Predictor)
    reg [4:0] lop; // Leading one position
    always @(*) begin
        lop = leading_one_predictor(mantissa_sum);  // Use a function to predict leading one
        mantissa_sum = mantissa_sum << lop;         // Shift left to normalize
        exp_result = exp_result - lop;              // Adjust exponent

        // Handle underflow
        if (exp_result < 8'h01) begin
            underflow = 1;
            result = 32'b0;  // Set result to zero on underflow
            zero = 1;
        end
    end

    // Step 5: Rounding (using guard, round, sticky bits)
    reg guard, round, sticky;
    always @(*) begin
        {guard, round, sticky} = mantissa_sum[2:0]; // Extract G, R, S bits
        mantissa_sum = mantissa_sum >> 2;           // Shift mantissa after rounding bits

        if (round && (guard || sticky)) begin
            mantissa_sum = mantissa_sum + 1;        // Perform rounding
            inexact = 1;                            // Set inexact flag if rounding occurred
        end

        // Handle overflow condition
        if (exp_result > 8'hFE) begin
            overflow = 1;
            result = {sign_result, 8'hFF, 23'b0};  // Result becomes infinity
        end else if (exp_result < 8'h01) begin
            underflow = 1;
            result = 32'b0;  // Underflow, result set to zero
        end else begin
            result = {sign_result, exp_result[7:0], mantissa_sum[22:0]};
        end

    end
endmodule

parameter EXP_WIDTH = 8;   // Exponent width
parameter MANT_WIDTH = 23; // Mantissa width (without hidden 1)

function [4:0] leading_one_predictor(input [MANT_WIDTH+2:0] value);
    integer i;
    reg [4:0] pos; 
    reg found; // Flag to indicate that the leading one has been found
    begin
        pos = 5'd0;   // Default value (no leading one found)
        found = 0;    // Initially, no leading one is found
        // Traverse the bits from MSB to LSB
        for (i = MANT_WIDTH + 2; i >= 0; i = i - 1) begin
            if (value[i] == 1 && !found) begin
                pos = i;   // Update position if leading one is found
                found = 1; // Set the flag to stop further updates
            end
        end
        leading_one_predictor = pos;  // Assign the final position
    end
endfunction


