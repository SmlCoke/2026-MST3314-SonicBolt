`timescale 1ns / 1ps

module conv_weight_row_rom #(
    parameter integer ROW_INDEX = 0
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rd_en,
    input  wire [2:0]   rd_group,
    output wire [223:0] weight_row_data
);

    reg [223:0] weight_row_data_reg;

    function [223:0] weight_lookup;
        input [2:0] group;
        begin
            weight_lookup = 224'h0;
            case (ROW_INDEX)
                0: begin
                    case (group)
                        3'd0: weight_lookup = 224'h4532240dd8310ac439ef08fc32fdefed2b240f1723db4301ffb7d2c1;
                        3'd1: weight_lookup = 224'h0d380735e616ee12fdeee6e415dcc7174141d3acb311bdda1bd9ccf1;
                        3'd2: weight_lookup = 224'h331b41012be9f7ef2be2eac51feff72ae403ef052c2f962cfe42fc4b;
                        3'd3: weight_lookup = 224'hbf5a352827b9a326b5b0f661f44dd3ceeceed5defd20de44f1f80df6;
                        3'd4: weight_lookup = 224'h4442e725c500dc45dbec1fdbdc1211f5db32e5eaf11701edfbfced08;
                        3'd5: weight_lookup = 224'hb4f4c01c2ed92c10c4c52e2fc822fc2f0edcdb272135f845e60833e7;
                        3'd6: weight_lookup = 224'he9ee06e4081f3dff1e134eca27030e03260c08d31f1a0f05f6f21dee;
                        3'd7: weight_lookup = 224'h2f131810f005d5bce106c2dbc709f652e31ef2dc1345ece40acefcde;
                    endcase
                end
                1: begin
                    case (group)
                        3'd0: weight_lookup = 224'h3fc5dd1c19ece3e00b3bee09cf03e1ef22ebdfeae32cc207dccdc603;
                        3'd1: weight_lookup = 224'h1c0831ed0fd7d7d129031915ef25ea342ecc3ec2b506c8c0e5f601f8;
                        3'd2: weight_lookup = 224'h28fe4019d1131e28e127f6ea0802092915f1d31131e6d91a37e4e8c8;
                        3'd3: weight_lookup = 224'hfd493ce9e3c9d8cdcc68584d3b4fade0da631a1b34403ce62017322d;
                        3'd4: weight_lookup = 224'hb3d047f4eee04526b138e405f4bbef160c111cdf1bf0120fe4f8ed2b;
                        3'd5: weight_lookup = 224'hf700befc1a280ddedbabd7f2abc7e1fdf807fb0bec483dc925acd82f;
                        3'd6: weight_lookup = 224'h264338eed844e940e11edfb7f791c231ec04ec3640131cf0070fe004;
                        3'd7: weight_lookup = 224'hc8fb06eb2e0025d3db18e1cf011402530ed5c02501a7c8143913e959;
                    endcase
                end
                2: begin
                    case (group)
                        3'd0: weight_lookup = 224'h35f1da05332ce614bcf8d3f4d5d10cd31bdc0e01e9e6370cd64000e2;
                        3'd1: weight_lookup = 224'h25fbdd262fd3e91cc3e7e5ca093307bd15d80bca3ff7f7c23909dd1b;
                        3'd2: weight_lookup = 224'hc5d63d1a010ac4f9302f2af2ed0e012c1be50d2d2bc601ba5ddace27;
                        3'd3: weight_lookup = 224'h23f911c51420c78040de2c6333fad5ecf22fc70312fc3bf1e200f2c5;
                        3'd4: weight_lookup = 224'hc3ba3fba002cdeb80428b4d33b23ec092a29012bd801fe1500fa1ce7;
                        3'd5: weight_lookup = 224'hbfda2bd4be39b93eb9eecf56e413e1ed20df2323112dd1f5e424bf37;
                        3'd6: weight_lookup = 224'hcf3ff8d5e8c703b5bc1a07df12db11e0182927e6471ffbda06e5deea;
                        3'd7: weight_lookup = 224'he939f90ef9d60e4cdb341934d533ae4b08f9082a0f012aeefdeb14c7;
                    endcase
                end
                3: begin
                    case (group)
                        3'd0: weight_lookup = 224'h2d162e42feeb1b3634d147f70529f3f6f9290bdd06a1d415ef052ed2;
                        3'd1: weight_lookup = 224'h0ffc25ed3eeb3727d2e4e103dde228d1f3c0c2393acf49c7d0f30cf9;
                        3'd2: weight_lookup = 224'hc9e109c9e821d9d51b1ceaccc92bfef2180923faf62ffbfd5fb43118;
                        3'd3: weight_lookup = 224'hb1cc040c42383b35de70acc6bdaded3a2861bc5662d8e0fbd8e21efe;
                        3'd4: weight_lookup = 224'h0c40e5091cf2f24cc2d80915d004042f272d32ffef0802dee81b1019;
                        3'd5: weight_lookup = 224'h0d0907f3bcfcbfedc202b7e3cf0713df18262e20f01cf31fdc12c0f1;
                        3'd6: weight_lookup = 224'h17da31c4cc060ae503260f331bf40edadfe1f0c7e5e60313f0e01104;
                        3'd7: weight_lookup = 224'hd9d12af8dbef14f3f52ab412c7cb490c2ce5e462cb4bb42a251d17e0;
                    endcase
                end
                4: begin
                    case (group)
                        3'd0: weight_lookup = 224'hf7e2e5dbd32205ce2216c6c4cd14d81e29ffdd052eff181625039dcb;
                        3'd1: weight_lookup = 224'hdf0df8dae2ec3c17282e0bca00e512c23cf7d4f03b25e101be40b81b;
                        3'd2: weight_lookup = 224'h0d17f51ee016b7d92119e029ca1bfee125282c1f174acd0210208ae9;
                        3'd3: weight_lookup = 224'hbfd6ccdc150d14dcc65640d9ccf1bbe2b7c201bc04232a1af4271b2b;
                        3'd4: weight_lookup = 224'h393a0dd1c916241523a5220f20b0e6e32edb3020fb00d81ae41df7f8;
                        3'd5: weight_lookup = 224'h37b8f225fe3ee6d7388f032d44101e0220e0fe082fe229541ac6fce6;
                        3'd6: weight_lookup = 224'h0f0ad70c214dded504bec9c82df011d73527e72a351afcf119de19e4;
                        3'd7: weight_lookup = 224'h00cc03fbf206d3321ee93240b7e629b7ac390046ba4fca001114d535;
                    endcase
                end
                5: begin
                    case (group)
                        3'd0: weight_lookup = 224'h46dc09ec2ac5203b001ec6212927da1d2220ddf3201cd5bd9b1447da;
                        3'd1: weight_lookup = 224'h20f1e103040f1ef1cb07e7081d362ae7d3ebc326602a45e42203d222;
                        3'd2: weight_lookup = 224'hc517fa0d1f1de330271001ced42d25f9fa270bd3e8553e3540e716e3;
                        3'd3: weight_lookup = 224'hefb73c31f300d39c5d6baa194159f8f83f2cffab08d53302101f4ac8;
                        3'd4: weight_lookup = 224'hde48dcb23248c2ef1ebedd53bab9e0fa1528ef32e6f702f5f6f2132f;
                        3'd5: weight_lookup = 224'h20fb0ff4d9ccca3b0b8abfe60c40edf9022af3ffe0c8d53ffbf1c52f;
                        3'd6: weight_lookup = 224'h10410005eb18e4420814f73e30280b0b202a29eb021f171be91e01e0;
                        3'd7: weight_lookup = 224'h061ec6e4c70ee5fe501eeafd1ec4d43ad14442f6c9e3f7253b2c40c9;
                    endcase
                end
                6: begin
                    case (group)
                        3'd0: weight_lookup = 224'h0035dbeff1ed3e1b39cec233070d2412f50ee2172a12d9e9c33e1e08;
                        3'd1: weight_lookup = 224'he2d9effe0be85005ec11f8cfd4204ac0bc34393d350006d7fe263816;
                        3'd2: weight_lookup = 224'hd4f1441a101bd817d3d62b331b0cfa262523070af951f94702c1deb0;
                        3'd3: weight_lookup = 224'h9dbe12c6434cd85e03fef61f00cc42d092371d0528d60fca1110e812;
                        3'd4: weight_lookup = 224'h0c1f0d2dd630c3563bc5cdffcf02ce06e12df5fef7e0d202fdf0021e;
                        3'd5: weight_lookup = 224'hc8ccd4efc216e48b8c004828121bf5db2d01fb230a4ae4ec2dda310b;
                        3'd6: weight_lookup = 224'h2f2d210be7fbcf2a28d524424947251dc9ea20f91c0bffeaf72105ed;
                        3'd7: weight_lookup = 224'hf1f9c0e7d603c4c41600b3f8073d3f12421369ba53fe073ef45106d8;
                    endcase
                end
                7: begin
                    case (group)
                        3'd0: weight_lookup = 224'h16f3f123d20af4ead91931ddce592cecd81e141334e9e551100af4f1;
                        3'd1: weight_lookup = 224'h03e2d9e326def6e8e612e326153c0bcbd034d34258c1f6fbe2cab705;
                        3'd2: weight_lookup = 224'h0e16f9321de81e06ec26e7d9e400fe27e311ecfbefcf8d99c9f1ddce;
                        3'd3: weight_lookup = 224'he1c019e30058defdd1075a912ab52ff73500deaed4ca181901fa3519;
                        3'd4: weight_lookup = 224'hfec428efb3eee059d1b5b05b3f09e0e7281421d7ef1323dbdd0ce51d;
                        3'd5: weight_lookup = 224'h380f40c7c3f23737f5b7e5c7b516f1fb1dffd820032101b2db4b0324;
                        3'd6: weight_lookup = 224'hc656fa2ab0ff22d30303f92cd738f228130ce3f7150ee8fb070c120a;
                        3'd7: weight_lookup = 224'he2d512fc02ec20d0cdcc101fd412273e9bcac7ed0ab7c61fc3ece031;
                    endcase
                end
                8: begin
                    case (group)
                        3'd0: weight_lookup = 224'hd7140fdbdd1d1af236bc48bc27d828fe07171c04284b42e217cac350;
                        3'd1: weight_lookup = 224'hdb2b0e25042e212fc447182dff03ab3b13c300c5d72639cbf7bdde03;
                        3'd2: weight_lookup = 224'h37d4180505c919dfe930e906d4120d271f0828dd0bd004c33cd62bac;
                        3'd3: weight_lookup = 224'h023b0ed3162213c20d090ce140a7e9dea1e92d4d3cf60af7eab53bf1;
                        3'd4: weight_lookup = 224'h0bdbbfef432fdc1a2f203c6034d002151ade2cd8dbf71bfc0711270f;
                        3'd5: weight_lookup = 224'h09dc0ce91731f4d4b32a1de025b6dc14ec2720063141c623fab9d5e7;
                        3'd6: weight_lookup = 224'h3ef4ef1937d2d7cbb73ef6f13a4d28d22bed1317d3200ff00004e3ee;
                        3'd7: weight_lookup = 224'hce3030dce4e9f3c0f1fa2a01eec1340eea14f105f2470deff55b29c6;
                    endcase
                end
                9: begin
                    case (group)
                        3'd0: weight_lookup = 224'h03cf0f25c3ca3322eaec2dd13253331910edf0ee0edfc248b4b7f93f;
                        3'd1: weight_lookup = 224'h01030afef3d208e0e0f50efe2c21c64bfdbe191e0d2be7190bc8f73f;
                        3'd2: weight_lookup = 224'he9f60017ea36e90a15f2c11fcbfc1b1102d5fe262b41b6c367ddd161;
                        3'd3: weight_lookup = 224'hb91a20e343143319a44532f938073a3926f8af12dad70844e8092cce;
                        3'd4: weight_lookup = 224'h14ebc5104322e840fee0e327fb0426e1d8de0efad61e12faed220f00;
                        3'd5: weight_lookup = 224'hb9ff3ef8f71633e2aab73936589dfefefcf32ee6211e3311c63799db;
                        3'd6: weight_lookup = 224'hc9230e4bc5beda1034b33142c90128f819222ec916eafdea260809e1;
                        3'd7: weight_lookup = 224'hfb20d9e3ccc70b42fb05e6e8242bab1147ba5852a4f814ffece131ce;
                    endcase
                end
                10: begin
                    case (group)
                        3'd0: weight_lookup = 224'h3fd7392eff234e04e0f4fdb7c134f917fc151bf3f1c81db8edac4fde;
                        3'd1: weight_lookup = 224'h150bd3fd1605f4d8de4bf626d8f52116cd1fbddfd2eee4ece3c0fdfb;
                        3'd2: weight_lookup = 224'h36e8383029def2262d0efafe0a18eb1828f22c1bfc5886e66a0c9c6a;
                        3'd3: weight_lookup = 224'hfa422540b224c6cfce0b0cf0e5a5432cc1e2a9fc2bd50ee301d7f3d1;
                        3'd4: weight_lookup = 224'h11de5d4c45e70047ae25f324c9351e30dc201b0cd9e9f5110ce5131a;
                        3'd5: weight_lookup = 224'h300f0d34c9d8e52a25ce269f0b41fff80bf8e5f621ddc13ad7df1818;
                        3'd6: weight_lookup = 224'hec35d4e1b1312a1c1effcd2b201d18c8e0e5d3f9d0e012210bf10ed9;
                        3'd7: weight_lookup = 224'hc6fce3fcfbcdf803f0d9cbe4b2dc4f2216b4cd50490ee52c344968c4;
                    endcase
                end
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_row_data_reg <= 224'd0;
        end else if (rd_en) begin
            weight_row_data_reg <= weight_lookup(rd_group);
        end
    end

    assign weight_row_data = weight_row_data_reg;

endmodule
