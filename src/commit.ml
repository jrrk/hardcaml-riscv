module Make(Ifs : Interfaces.S)(B : HardCaml.Comb.S) = struct

  open B
  open Ifs

  let name = "com"

  let (--) s n = s -- ("com_" ^ n)

  let commit ~mem ~csrs ~csr_rdata ~prv =
    let open Stage in
    let open Stages in
    let open Class in
    let p = mem in
    let i = p.iclass in
    let sel b = let b = Config.T.Enum_t.from_enum b in p.insn.[b:b] in

    let branch = (sel `jal |: sel `jalr |: (i.bra &: p.branch)) -- "branch" in
    let pc_next = p.pc +:. 4 in

    let rdd = 
      mux2 (sel `jal |: sel `jalr) 
        pc_next 
        (mux2 i.csr csr_rdata p.rdd)
    in
    let pc = 
      pmux [
        branch, p.rdd;
        i.ecall, (consti 32 0x100); (* XXX should come from CSRs *)
      ] pc_next 
    in

    let csrs_wr = Ifs.Csr_regs.(map (fun (n,b) -> gnd, zero b) t) in 

    let invalid_instr_level = prv <: i.level in

    let csr_reg_write, csr_file_write = 
      let no_reg_write = p.rad_zero in
      let no_file_write = (~: (sel `csrrw |: sel `csrrwi)) &: p.ra1_zero in
      p.iclass.csr &: (~: no_reg_write),
      p.iclass.csr &: (~: no_file_write)
    in
    let csr_trap = 
      (~: (p.csr.Csr_ctrl.csr_address_valid)) |:
      (p.csr.Csr_ctrl.csr_read_only &: csr_file_write)
    in

    let invalid_instr_trap = 
      p.exn.Exn.invalid_instr_trap |: invalid_instr_level |: csr_trap
    in
    let trap_n = ~: invalid_instr_trap in

    { mem with 
      branch; rdd; 
      rwe = (p.rwe |: csr_reg_write) &: trap_n;
      pc = pc.[31:1] @: gnd; 
      exn = { Exn.invalid_instr_trap; invalid_instr_level };
      csr = 
        { mem.csr with 
          Csr_ctrl.csr_reg_write = csr_reg_write &: trap_n; 
          csr_file_write = csr_file_write &: trap_n; 
        };
    }, csrs_wr

  let f ~inp ~comb ~pipe = 
    let open Stages in
    let csrs = Ifs.Csr_regs_ex.zero in
    fst @@ commit ~mem:pipe.mem ~csrs ~csr_rdata:(zero Ifs.xlen) ~prv:gnd

end


(*
  on exception:

   mstatus.prv=M mstatus.ie=0
   mcause.interrupt=0 mcause.exception_code=???
   mip/mie???

      I  EC    Desc
   -------------------------------------------
      0   0    Instruction address misaligned
      0   1    Instruction access fault
      0   2    Illegal instruction
      0   3    Breakpoint
      0   4    Load address misaligned
      0   5    Load access fault
      0   6    Store/AMO address misaligned
      0   7    Store/AMO access fault
      0   8    Environment call from U-mode
      0   9    Environment call from S-mode
      0   10   Environment call from H-mode
      0   11   Environment call from M-mode
      0   ≥12  Reserved
      1   0    Software interrupt
      1   1    Timer interrupt
      1   ≥2   Reserved

  mbadaddr if - instr/data access or alignment error
*)

