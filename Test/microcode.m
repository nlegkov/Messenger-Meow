
jsr: mem, data, word, sp_dec, sp_asrt0, pc_asrtD
     mem, word, read, pc_asrt0, pc_latch


rti: mem, data, word, read, sp_asrt0, pc_latch, sp_inc
     mem, data, word, read, sp_asrt0, ps_latch_word, sp_inc


pupc: mem, data, word, sp_dec, sp_asrt0, pc_asrtD


popc: mem, data, word, read, sp_asrt0, pc_latch, sp_inc


int: mem, data, word, sp_asrt0, sp_dec, ps_asrtD
     mem, data, word, sp_asrt0, sp_dec, pc_asrtD
     mem, read, word, imm_asrt1, pc_latch
     mem, read, word, imm_asrt1, ps_latch_word





ldw_mmio: mem, data, word, read, r_asrt0, r_latch


ldb_mmio: mem, data, read, r_asrt0, r_latch


stw_mmio: mem, data, word, r_asrt0, r_asrtD


stb_mmio: mem, data, r_asrt0, r_asrtD
