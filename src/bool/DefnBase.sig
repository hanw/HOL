signature DefnBase =
sig
  type term = Term.term
  type thm  = Thm.thm

 datatype defn
   = ABBREV  of {eqn:thm, bind:string}
   | PRIMREC of {eqs:thm, ind:thm, bind:string}
   | NONREC  of {eqs:thm, ind:thm, SV:term list, stem:string}
   | STDREC  of {eqs:thm list, ind:thm, R:term,SV:term list,stem:string}
   | MUTREC  of {eqs:thm list, ind:thm, R:term,SV:term list,
                 stem:string,union:defn}
   | NESTREC of {eqs:thm list, ind:thm, R:term,SV:term list,
                 stem:string,aux:defn}


  val pp_defn : ppstream -> defn -> unit


  (* Used to control context tracking during termination
     condition extraction *)

  val read_congs  : unit -> thm list
  val write_congs : thm list -> unit
  val add_cong : thm -> unit

  val export_cong : string -> unit

end
