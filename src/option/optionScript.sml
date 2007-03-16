(* =======================================================================*)
(* FILE		: optionScript.sml                                        *)
(* DESCRIPTION  : Creates a theory of SML like options         	          *)
(* WRITES FILES	: option.th						  *)
(*									  *)
(* AUTHOR	: (c) D. Syme 1988					  *)
(* DATE		: 95.04.25						  *)
(* REVISED	: (Konrad Slind) Oct 9.97 to eliminate usage of           *)
(*                recursive types package. Follows the development of     *)
(*                Elsa Gunter in her formalization of partial functions.  *)
(*                                                                        *)
(*                Dec.1998, in order to fit in with Datatype scheme       *)
(* =======================================================================*)

open HolKernel Parse boolLib metisLib;

(*---------------------------------------------------------------------------
     Make sure that sumTheory and oneTheory is loaded.
 ---------------------------------------------------------------------------*)

local open sumTheory oneTheory in end;

(* ---------------------------------------------------------------------*)
(* Create the new theory						*)
(* ---------------------------------------------------------------------*)

val _ = new_theory "option";

(*---------------------------------------------------------------------------*
 * Define the new type. The representing type is 'a + one. The development   *
 * is adapted from Elsa Gunter's development of an option type in her        *
 * holML formalization (she called it "lift").                               *
 *---------------------------------------------------------------------------*)

val option_TY_DEF =
 new_type_definition
  ("option",
   prove(Term`?x:'a + one. (\x.T) x`,
          BETA_TAC THEN EXISTS_TAC(--`x:'a + one`--) THEN ACCEPT_TAC TRUTH));

(*---------------------------------------------------------------------------*
 *  val option_REP_ABS_DEF =                                                 *
 *     |- (!a. option_ABS (option_REP a) = a) /\                             *
 *        (!r. (\x. T) r = option_REP (option_ABS r) = r)                    *
 *---------------------------------------------------------------------------*)

val option_REP_ABS_DEF =
     define_new_type_bijections
     {name = "option_REP_ABS_DEF",
      ABS = "option_ABS", REP = "option_REP",
      tyax = option_TY_DEF};

fun reduce thm = REWRITE_RULE[](BETA_RULE thm);

(*---------------------------------------------------------------------------*
 * option_ABS_ONE_ONE = |- !r r'. (option_ABS r = option_ABS r') = r = r'    *
 * option_ABS_ONTO = |- !a. ?r. a = option_ABS r                             *
 * option_REP_ONE_ONE = |- !a a'. (option_REP a = option_REP a') = a = a'    *
 * option_REP_ONTO = |- !r. ?a. r = option_REP a                             *
 *---------------------------------------------------------------------------*)

val option_ABS_ONE_ONE = reduce(prove_abs_fn_one_one option_REP_ABS_DEF);
val option_ABS_ONTO    = reduce(prove_abs_fn_onto option_REP_ABS_DEF);
val option_REP_ONE_ONE = prove_rep_fn_one_one option_REP_ABS_DEF;
val option_REP_ONTO    = reduce(prove_rep_fn_onto option_REP_ABS_DEF);

val SOME_DEF = new_definition("SOME_DEF",Term`!x. SOME x = option_ABS(INL x)`);
val NONE_DEF = new_definition("NONE_DEF",Term`NONE = option_ABS(INR one)`);

val option_CASES_orig = prove
(Term`!opt. (?x. opt = SOME x) \/ (opt = NONE)`,
GEN_TAC THEN PURE_REWRITE_TAC[SOME_DEF,NONE_DEF]
 THEN PURE_ONCE_REWRITE_TAC[SYM(SPEC_ALL option_REP_ONE_ONE)]
 THEN PURE_ONCE_REWRITE_TAC[reduce(option_REP_ABS_DEF)]
 THEN STRIP_ASSUME_TAC (ISPEC (--`option_REP opt`--) sumTheory.ISL_OR_ISR)
 THENL
 [DISJ1_TAC THEN IMP_RES_TAC sumTheory.INL THEN POP_ASSUM (SUBST1_TAC o SYM)
      THEN EXISTS_TAC (--`OUTL (option_REP opt)`--) THEN REFL_TAC,
  DISJ2_TAC THEN IMP_RES_TAC sumTheory.INR THEN POP_ASSUM (SUBST1_TAC o SYM)
      THEN ONCE_REWRITE_TAC[oneTheory.one] THEN REFL_TAC]);

val option_Axiom = store_thm (
  "option_Axiom",
  Term`!e f:'a -> 'b. ?fn. (!x. fn (SOME x) = f x) /\ (fn NONE = e)`,
  REPEAT GEN_TAC THEN
  PURE_REWRITE_TAC[SOME_DEF,NONE_DEF] THEN
  STRIP_ASSUME_TAC
     (BETA_RULE
        (ISPECL [--`\x. f x`--, --`\x:one.(e:'b)`--]
         (INST_TYPE [Type.beta |-> Type`:one`]
          sumTheory.sum_Axiom))) THEN
  EXISTS_TAC (--`\x:'a option. h(option_REP x):'b`--) THEN BETA_TAC THEN
  ASM_REWRITE_TAC[reduce option_REP_ABS_DEF]);

val option_induction = store_thm (
  "option_induction",
  Term`!P. P NONE /\ (!a. P (SOME a)) ==> !x. P x`,
  GEN_TAC THEN PURE_REWRITE_TAC [SOME_DEF, NONE_DEF] THEN
  REPEAT STRIP_TAC THEN
  ONCE_REWRITE_TAC [GSYM (CONJUNCT1 option_REP_ABS_DEF)] THEN
  SPEC_TAC (Term`option_REP (x:'a option)`, Term`s:'a + one`) THEN
  HO_MATCH_MP_TAC sumTheory.sum_INDUCT THEN
  ONCE_REWRITE_TAC [oneTheory.one] THEN ASM_REWRITE_TAC []);

val FORALL_OPTION = Q.store_thm
 ("FORALL_OPTION",
  `(!opt. P opt) = P NONE /\ !x. P (SOME x)`,
  METIS_TAC [option_induction]);

val SOME_11 = store_thm("SOME_11",
  Term`!x y :'a. (SOME x = SOME y) = (x=y)`,
  REWRITE_TAC [SOME_DEF,option_ABS_ONE_ONE,sumTheory.INR_INL_11]);

val (NOT_NONE_SOME,NOT_SOME_NONE) =
 let val thm = TAC_PROOF(([], Term`!x:'a. ~(NONE = SOME x)`),
                  REWRITE_TAC [SOME_DEF,NONE_DEF,
                               option_ABS_ONE_ONE,sumTheory.INR_neq_INL])
 in
   (save_thm("NOT_NONE_SOME", thm),
    save_thm("NOT_SOME_NONE", GSYM thm))
  end;

val option_nchotomy = save_thm("option_nchotomy",
 ONCE_REWRITE_RULE [DISJ_SYM] option_CASES_orig);

val option_case_def = Prim_rec.new_recursive_definition
  {name="option_case_def",
   rec_axiom=option_Axiom,
   def = Term`(option_case u f NONE = u) /\
              (option_case (u:'b) f (SOME (x:'a)) = f x)`};

val OPTION_MAP_DEF = Prim_rec.new_recursive_definition
 {name="OPTION_MAP_DEF",
  rec_axiom=option_Axiom,
  def =
  Term`(OPTION_MAP (f:'a->'b) (SOME x) = SOME (f x)) /\
       (OPTION_MAP f NONE = NONE)`};

val IS_SOME_DEF = Prim_rec.new_recursive_definition
  {name="IS_SOME_DEF",
   rec_axiom=option_Axiom,
   def = Term`(IS_SOME (SOME x) = T) /\ (IS_SOME NONE = F)`};

val IS_NONE_DEF = Prim_rec.new_recursive_definition {
  name = "IS_NONE_DEF",
  rec_axiom = option_Axiom,
  def = Term`(IS_NONE (SOME x) = F) /\ (IS_NONE NONE = T)`};

val THE_DEF = Prim_rec.new_recursive_definition
  {name="THE_DEF",
   rec_axiom=option_Axiom,
   def = Term `THE (SOME x) = x`};

val OPTION_JOIN_DEF = Prim_rec.new_recursive_definition
  {name = "OPTION_JOIN_DEF",
   rec_axiom = option_Axiom,
   def = Term`(OPTION_JOIN NONE = NONE) /\
              (OPTION_JOIN (SOME x) = x)`};

val option_rws =
    [IS_SOME_DEF, THE_DEF, IS_NONE_DEF, option_nchotomy,
     NOT_NONE_SOME,NOT_SOME_NONE, SOME_11, option_case_def,
     OPTION_MAP_DEF, OPTION_JOIN_DEF];

val ex1_rw = prove(Term`!x. (?y. x = y) /\ (?y. y = x)`,
   GEN_TAC THEN CONJ_TAC THEN EXISTS_TAC (Term`x`) THEN REFL_TAC);

fun OPTION_CASES_TAC t = STRUCT_CASES_TAC (ISPEC t option_nchotomy);

val IS_NONE_EQ_NONE = Q.store_thm(
  "IS_NONE_EQ_NONE",
  `!x. IS_NONE x = (x = NONE)`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);

val NOT_IS_SOME_EQ_NONE = Q.store_thm(
  "NOT_IS_SOME_EQ_NONE",
  `!x. ~(IS_SOME x) = (x = NONE)`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);

val IS_SOME_EQ_EXISTS = Q.prove(
 `!x. IS_SOME x = (?v. x = SOME v)`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC (ex1_rw::option_rws)
);


val IS_SOME_IMP_SOME_THE_CANCEL = Q.prove(
`!x:'a option. IS_SOME x ==> (SOME (THE x) = x)`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);

val option_case_ID = Q.store_thm(
  "option_case_ID",
  `!x:'a option. option_case NONE SOME x = x`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);

val IS_SOME_option_case_SOME = Q.prove(
`!x:'a option. IS_SOME x ==> (option_case e SOME x = x)`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);

val option_case_SOME_ID = Q.store_thm(
  "option_case_SOME_ID",
  `!x:'a option. (option_case x SOME x = x)`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);

val IS_SOME_option_case = Q.prove(
`!x:'a option. IS_SOME x ==> (option_case e (f:'a->'b) x = f (THE x))`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);


val IS_NONE_option_case = Q.prove(
`!x:'a option. IS_NONE x ==> (option_case e f x = (e:'b))`,
    GEN_TAC
    THEN OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws
);


val option_CLAUSES = save_thm("option_CLAUSES",
     LIST_CONJ ([SOME_11,THE_DEF,NOT_NONE_SOME,NOT_SOME_NONE]@
                (CONJUNCTS IS_SOME_DEF)@
                [IS_NONE_EQ_NONE,
                 NOT_IS_SOME_EQ_NONE,
                 IS_SOME_IMP_SOME_THE_CANCEL,
                 option_case_ID,
                 option_case_SOME_ID,
                 IS_NONE_option_case,
                 IS_SOME_option_case,
                 IS_SOME_option_case_SOME]@
                 CONJUNCTS option_case_def@
                 CONJUNCTS OPTION_MAP_DEF@
                 CONJUNCTS OPTION_JOIN_DEF));

val option_case_compute = Q.store_thm
("option_case_compute",
 `option_case (e:'b) f (x:'a option) =
  if IS_SOME x then f (THE x) else e`,
    OPTION_CASES_TAC (--`(x :'a option)`--)
    THEN ASM_REWRITE_TAC option_rws);

val OPTION_MAP_EQ_SOME = Q.store_thm(
  "OPTION_MAP_EQ_SOME",
  `!f (x:'a option) y.
         (OPTION_MAP f x = SOME y) = ?z. (x = SOME z) /\ (y = f z)`,
  REPEAT GEN_TAC THEN OPTION_CASES_TAC (--`x:'a option`--) THEN
  simpLib.SIMP_TAC boolSimps.bool_ss
    [SOME_11, NOT_NONE_SOME, NOT_SOME_NONE, OPTION_MAP_DEF] THEN
  mesonLib.MESON_TAC []);

val OPTION_MAP_EQ_NONE = Q.store_thm(
  "OPTION_MAP_EQ_NONE",
  `!f x.  (OPTION_MAP f x = NONE) = (x = NONE)`,
  REPEAT GEN_TAC THEN OPTION_CASES_TAC (--`x:'a option`--) THEN
  REWRITE_TAC [option_CLAUSES]);

val OPTION_MAP_EQ_NONE_both_ways = Q.store_thm(
  "OPTION_MAP_EQ_NONE_both_ways",
  `((OPTION_MAP f x = NONE) = (x = NONE)) /\
   ((NONE = OPTION_MAP f x) = (x = NONE))`,
  REWRITE_TAC [OPTION_MAP_EQ_NONE] THEN
  CONV_TAC (LAND_CONV (ONCE_REWRITE_CONV [EQ_SYM_EQ])) THEN
  REWRITE_TAC [OPTION_MAP_EQ_NONE]);

val OPTION_MAP_CONG = store_thm(
  "OPTION_MAP_CONG",
  ``!opt1 opt2 f1 f2.
      (opt1 = opt2) /\ (!x. (opt2 = SOME x) ==> (f1 x = f2 x)) ==>
      (OPTION_MAP f1 opt1 = OPTION_MAP f2 opt2)``,
  REPEAT STRIP_TAC THEN ASM_REWRITE_TAC [] THEN
  Q.SPEC_THEN `opt2` FULL_STRUCT_CASES_TAC option_nchotomy THEN
  REWRITE_TAC [OPTION_MAP_DEF, SOME_11] THEN
  FIRST_X_ASSUM MATCH_MP_TAC THEN REWRITE_TAC [SOME_11])
val _ = DefnBase.export_cong "OPTION_MAP_CONG"



val OPTION_JOIN_EQ_SOME = Q.store_thm(
  "OPTION_JOIN_EQ_SOME",
  `!(x:'a option option) y. (OPTION_JOIN x = SOME y) = (x = SOME (SOME y))`,
  GEN_TAC THEN
  Q.SUBGOAL_THEN `(x = NONE) \/ (?z. x = SOME z)` STRIP_ASSUME_TAC THENL [
    MATCH_ACCEPT_TAC option_nchotomy,
    ALL_TAC,
    ALL_TAC
  ] THEN ASM_REWRITE_TAC option_rws THEN
  OPTION_CASES_TAC (--`z:'a option`--) THEN
  ASM_REWRITE_TAC option_rws);


val option_case_cong =
  save_thm("option_case_cong",
      Prim_rec.case_cong_thm option_nchotomy option_case_def);

val _ = adjoin_to_theory
{sig_ps = SOME (fn ppstrm =>
  let val S = PP.add_string ppstrm
      fun NL() = PP.add_newline ppstrm
  in
    S "val option_Induct : thm"; NL();
    S "val option_CASES : thm";  NL()
  end),
 struct_ps = SOME (fn ppstrm =>
  let val S = PP.add_string ppstrm
      fun NL() = PP.add_newline ppstrm
  in
    S "val _ = TypeBase.write";                              NL();
    S "  [TypeBasePure.mk_datatype_info";                    NL();
    S "     {ax=TypeBasePure.ORIG option_Axiom,";            NL();
    S "      case_def=option_case_def,";                     NL();
    S "      case_cong=option_case_cong,";                   NL();
    S "      induction=TypeBasePure.ORIG option_induction,"; NL();
    S "      nchotomy=option_nchotomy,";                     NL();
    S "      size=NONE,";                                    NL();
    S "      encode=NONE,";                                  NL();
    S "      fields=[],";                                    NL();
    S "      accessors=[],";                                 NL();
    S "      updates=[],";                                   NL();
    S "      lift=SOME(mk_var(\"optionSyntax.lift_option\",Parse.Type`:'type -> ('a -> 'term) -> 'a option -> 'term`)),";
    NL();
    S "      one_one=SOME SOME_11,";                         NL();
    S "      distinct=SOME NOT_NONE_SOME}];";                NL();
    NL();
    S "val option_Induct = Rewrite.ONCE_REWRITE_RULE ";               NL();
    S "                      [boolTheory.CONJ_SYM] option_induction"; NL();
    S "val option_CASES = Rewrite.ONCE_REWRITE_RULE ";                NL();
    S "                      [boolTheory.DISJ_SYM] option_nchotomy";
    NL();NL();
    S "val _ = let open computeLib";                            NL();
    S "        in add_funs (map lazyfy_thm";                    NL();
    S "               [NOT_NONE_SOME,NOT_SOME_NONE,SOME_11,";   NL();
    S "                option_case_compute,OPTION_MAP_DEF,";    NL();
    S "                IS_SOME_DEF,IS_NONE_DEF,THE_DEF,";       NL();
    S "                OPTION_JOIN_DEF])";                      NL();
    S "        end;"
  end)};

val _ = TypeBase.write
  [TypeBasePure.mk_datatype_info
     {ax=TypeBasePure.ORIG option_Axiom,
      case_def=option_case_def,
      case_cong=option_case_cong,
      induction=TypeBasePure.ORIG option_induction,
      nchotomy=option_nchotomy,
      size=NONE,
      encode=NONE,
      fields=[], accessors=[], updates=[],
      lift=SOME(mk_var("optionSyntax.lift_option",
                Parse.Type`:'type -> ('a -> 'term) -> 'a option -> 'term`)),
      one_one=SOME SOME_11,
      distinct=SOME NOT_NONE_SOME}];


val _ = BasicProvers.export_rewrites
          ["OPTION_MAP_EQ_SOME", "OPTION_MAP_EQ_NONE_both_ways", "THE_DEF",
           "IS_SOME_DEF", "IS_NONE_EQ_NONE", "NOT_IS_SOME_EQ_NONE",
           "option_case_ID", "option_case_SOME_ID", "option_case_def",
           "OPTION_MAP_DEF", "OPTION_JOIN_DEF", "SOME_11", "NOT_SOME_NONE"];


(*---------------------------------------------------------------------------*)
(* Need to install the constructors for options into the const map.          *)
(*---------------------------------------------------------------------------*)

val _ = ConstMapML.insert(Term.prim_mk_const{Name="SOME",Thy="option"});
val _ = ConstMapML.insert(Term.prim_mk_const{Name="NONE",Thy="option"});

val _ = adjoin_to_theory
{sig_ps = NONE,
 struct_ps = SOME (fn ppstrm =>
  let val S = PP.add_string ppstrm
      fun NL() = PP.add_newline ppstrm
  in S "val _ = ConstMapML.insert (Term.prim_mk_const{Name=\"SOME\",Thy=\"option\"});";
     NL();
     S "val _ = ConstMapML.insert (Term.prim_mk_const{Name=\"NONE\",Thy=\"option\"});";
     NL(); NL()
  end)};

(*---------------------------------------------------------------------------*)
(* Export ML versions of option functions                                    *)
(*---------------------------------------------------------------------------*)

val THE_NONE = Q.prove
(`THE NONE = FAIL THE ^(mk_var("applied to NONE",bool)) NONE`,
  REWRITE_TAC [combinTheory.FAIL_THM]);

val _ =
 let open EmitML combinSyntax
 in emitML (!Globals.emitMLDir)
      ("option",
        MLSIG "datatype option = datatype Option.option" ::
        MLSTRUCT "datatype option = datatype Option.option"
        ::
        map DEFN
         [OPTION_MAP_DEF, IS_SOME_DEF, IS_NONE_DEF,
          CONJ THE_NONE THE_DEF, OPTION_JOIN_DEF])
 end;

val _ = export_theory();
