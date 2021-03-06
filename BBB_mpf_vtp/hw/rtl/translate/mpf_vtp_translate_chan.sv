//
// Copyright (c) 2020, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

//
// Protocol-independent address translation for a single DMA request channel.
// Responses are returned in request order.
//

`include "cci_mpf_if.vh"

module mpf_vtp_translate_chan
  #(
    // Requests pass through the module as opaque values. Set the size
    // to match the opaque_* ports.
    parameter N_OPAQUE_BITS = 0,

    // Some requests don't require translation. For example, non-SOP
    // beats in write bursts. These are stored here in a FIFO and not
    // sent to VTP. For some channels, the FIFO can be the same size
    // as the available VTP buffering. Reads have this property, since
    // each read request is a single beat. For writes, having the FIFO
    // large enough to store non-SOP beats allows VTP to pipeline
    // multiple translations. Typically, USE_LARGE_FIFO should be
    // set to 1 for write pipelines with bursts and set to 0 for
    // read pipelines or single-beat write pipelines.
    parameter USE_LARGE_FIFO = 0
    )
   (
    input  logic clk,
    input  logic reset,

    output logic rsp_valid,
    output logic [N_OPAQUE_BITS-1 : 0] opaque_rsp,
    input  logic deq_en,

    // New request is accepted when req_valid and not full. req_valid is
    // ignored when VTP is full.
    input  logic req_valid,
    input  logic [N_OPAQUE_BITS-1 : 0] opaque_req,
    output logic full,

    // Request: commands to VTP (e.g. address to translate)
    input  mpf_vtp_pkg::t_mpf_vtp_port_wrapper_req vtp_req,

    // Response from VTP (e.g. whether translation was successful)
    output mpf_vtp_pkg::t_mpf_vtp_port_wrapper_rsp vtp_rsp,
    // Did the response use VTP or just get buffered here? Only requests
    // with the addrIsVirtual bit set are routed to VTP. The vtp_rsp
    // port has meaning only when rsp_used_vtp and rsp_valid are set.
    output logic rsp_used_vtp,

    mpf_vtp_port_if.to_slave vtp_port
    );

    import mpf_vtp_pkg::*;

    logic pipe_notFull;
    logic vtp_notEmpty;
    logic vtp_notFull;
    logic fifo_notFull;
    logic fifo_notEmpty;

    // Responses with no translation requirement use only the FIFO.
    // When translation is required, both VTP and the FIFO are used.
    assign rsp_valid = (vtp_notEmpty || ! rsp_used_vtp) && fifo_notEmpty;

    assign pipe_notFull = vtp_notFull && fifo_notFull;
    assign full = ~pipe_notFull;

    // Forward request to VTP
    mpf_svc_vtp_port_wrapper_ordered
      tr
       (
        .clk,
        .reset,

        .vtp_port,
        // Send to VTP only when translation is required
        .reqEn(req_valid && pipe_notFull && vtp_req.addrIsVirtual),
        .req(vtp_req),
        .notFull(vtp_notFull),
        .reqIdx(),

        .rspValid(vtp_notEmpty),
        .rsp(vtp_rsp),
        .rspDeqEn(deq_en && rsp_used_vtp),
        .rspIdx()
        );

    logic [N_OPAQUE_BITS-1 : 0] internal_opaque_rsp;
    logic internal_rsp_used_vtp;
    logic internal_notEmpty, internal_notFull;

    // Hold the opaque request during lookup. The VTP port wrapper provides
    // up to MPF_VTP_MAX_SVC_REQS indices. The addresses used for storage are
    // generated by the VTP port as part of its request tracking logic.
    generate
        if (USE_LARGE_FIFO)
        begin : lg
            // Inbound FIFO
            cci_mpf_prim_fifo_bram
              #(
                .N_ENTRIES(512),
                .N_DATA_BITS(N_OPAQUE_BITS + 1)
                )
             tr_meta
               (
                .clk,
                .reset,

                // Record whether the request was also sent to VTP in the low bit
                .enq_data({ opaque_req, vtp_req.addrIsVirtual }),
                .enq_en(req_valid && pipe_notFull),
                .notFull(fifo_notFull),
                .almostFull(),

                .first({ internal_opaque_rsp, internal_rsp_used_vtp }),
                .deq_en(internal_notEmpty && internal_notFull),
                .notEmpty(internal_notEmpty)
                );
        end
        else
        begin : sm
            cci_mpf_prim_fifo_lutram
              #(
                .N_ENTRIES(MPF_VTP_MAX_SVC_REQS),
                .N_DATA_BITS(N_OPAQUE_BITS + 1),
                .REGISTER_OUTPUT(1)
                )
             tr_meta
               (
                .clk,
                .reset,

                // Record whether the request was also sent to VTP in the low bit
                .enq_data({ opaque_req, vtp_req.addrIsVirtual }),
                .enq_en(req_valid && pipe_notFull),
                .notFull(fifo_notFull),
                .almostFull(),

                .first({ internal_opaque_rsp, internal_rsp_used_vtp }),
                .deq_en(internal_notEmpty && internal_notFull),
                .notEmpty(internal_notEmpty)
                );
        end
    endgenerate

    // Output fifo2 for timing
    cci_mpf_prim_fifo2
      #(
        .N_DATA_BITS(N_OPAQUE_BITS + 1)
        )
     tr_meta_out
       (
        .clk,
        .reset,

        // Record whether the request was also sent to VTP in the low bit
        .enq_data({ internal_opaque_rsp, internal_rsp_used_vtp }),
        .enq_en(internal_notEmpty && internal_notFull),
        .notFull(internal_notFull),

        .first({ opaque_rsp, rsp_used_vtp }),
        .deq_en,
        .notEmpty(fifo_notEmpty)
        );

endmodule // mpf_vtp_translate_chan_ordered
