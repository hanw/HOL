structure DataSize :> DataSize =
struct

open HolKernel Parse boolLib Prim_rec
val ERR = mk_HOL_ERR "DataSize";

val num = numSyntax.num

val defn_const =
  #1 o strip_comb o lhs o #2 o strip_forall o hd o strip_conj o concl;

val head = Lib.repeat rator;

fun tyconst_names ty =
  let val {Thy,Tyop,Args} = dest_thy_type ty
  in (Thy,Tyop)
  end;

local open Portable
      fun num_variant vlist v =
        let val counter = ref 0
            val names = map (fst o dest_var) vlist
            val (Name,Ty) = dest_var v
            fun pass str =
               if mem str names
               then (inc counter; pass (Name^Lib.int_to_string(!counter)))
               else str
        in mk_var(pass Name,  Ty)
        end
      fun next_nm avoids s = Lexis.gen_variant Lexis.tyvar_vary avoids s
      fun gen_tyvs avoids nextty (kd::kds) =
            let val (name,_) = dest_var_type nextty
                val new_name = next_nm avoids name
                val newtyv = mk_var_type(new_name, kd)
            in newtyv :: gen_tyvs (new_name::avoids) newtyv kds
            end
        | gen_tyvs avoids nextty [] = []
      fun size_ty avoids ty =
        let val (s,kd) = dest_var_type ty
                         handle HOL_ERR e => ("", kind_of ty)
        in if is_type_kind kd then ty --> num
           else if is_arrow_kind kd then
             let val (args,res) = strip_arrow_kind kd
                 val arg_tyvs = gen_tyvs (s::avoids) alpha args
                 val arg_sz_tys = map (size_ty (s::avoids)) arg_tyvs
                 val resty = list_mk_app_type(ty, arg_tyvs)
                 val _ = assert (equal res) (kind_of resty)
                 val res_sz_ty = (* resty --> num *) size_ty (s::avoids) resty
             in list_mk_univ_type (arg_tyvs, foldr (op -->) res_sz_ty arg_sz_tys)
             end
           else (* kd is a kind variable *)
             let val (k,rk) = dest_var_kind kd
                 val k' = next_nm (s::avoids) k
                 val ty' = mk_var_type (k', kd ==> typ rk) (* or typ 0 *)
             in
               mk_app_type (ty', ty) --> num
             end
(* alternatively,
             let val k = dest_var_kind kd
                 val k0 = String.extract(k, 1, NONE)
                 val s' = s ^ "_" ^ k0
                 val ty' = mk_var_type (s', typ, rk)
             in (* raise ERR "mk_tyvar_size"
                  ("kind of type variable "^s^" contains a kind variable "^k) *)
               ty' --> num
             end
*)
        end
in
fun mk_tyvar_size vty (V,away) =
  let val fty = size_ty [] vty (* vty --> num *)
      val v = num_variant away (mk_var("f", fty))
  in (v::V, v::away)
  end
end;

fun tysize_env db =
     Option.map fst o
     Option.composePartial (TypeBasePure.size_of, TypeBasePure.prim_get db)

(*---------------------------------------------------------------------------*
 * Term size, as a function of types. The function gamma maps type           *
 * operator "ty" to term "ty_size". Types not registered in gamma are        *
 * translated into the constant function that returns 0. The function theta  *
 * maps a type variable (say 'a) to a term variable "f" of type 'a -> num.   *
 *                                                                           *
 * When actually building a measure function, the behaviour of theta is      *
 * changed to be such that it maps type variables to the constant function   *
 * that returns 0.                                                           *
 *---------------------------------------------------------------------------*)

local fun drop [] ty = fst(dom_rng ty)
        | drop (_::t) ty = drop t (snd(dom_rng ty));
      fun lose 0 ty = ty
        | lose n ty = lose (n-1) (fst (dest_app_type ty))
      fun Kzero ty = mk_abs(mk_var("v",ty), numSyntax.zero_tm)
      fun OK f ty M =
         let val (Rator,Rand) = dest_comb M
         in (eq Rator f) andalso is_var Rand andalso (type_of Rand = ty)
         end
      fun match_mk_comb (opr,arg) =
         let val (dom,rng) = dom_rng (type_of opr)
             val (uvs,dom') = strip_univ_type dom
             val aty = type_of arg
         in if eq_ty dom aty then mk_comb(opr,arg)
            else let val (tyS,kdS,rkS) = Type.om_match_type aty dom'
                     val arg' = inst_rk_kd_ty (tyS,kdS,rkS) arg
                     val arg'' = list_mk_tyabs(uvs, arg')
                 in mk_comb(opr,arg'')
                 end
         end
      fun list_match_mk_comb (opr,[]) = opr
        | list_match_mk_comb (opr, arg::args) = list_match_mk_comb(match_mk_comb(opr,arg),args)
in
fun tysize (theta,omega,gamma) clause ty =
 case theta ty
  of SOME fvar => fvar
   | NONE =>
      case omega ty
       of SOME (_,[]) => raise ERR "tysize" "bug: no assoc for nested"
        | SOME (_,[(f,szfn)]) => szfn
        | SOME (_,alist) => snd
             (first (fn (f,sz) => Lib.can (find_term(OK f ty)) (rhs clause))
                  alist)
        | NONE =>
           let val {Tyop,Thy,Args} = dest_thy_type ty
               val Kind = valOf (op_kind {Tyop=Tyop, Thy=Thy})
               val kind_args = fst(strip_arrow_kind Kind)
           in case gamma (Thy,Tyop)
               of SOME f =>
                   let val vty0 = drop kind_args (*Args*) (type_of f)
                       val vty = lose (length kind_args - length Args) vty0
                       val (tyS,kdS,rkS) = Type.om_match_type vty ty
                    in list_mk_comb(inst_rk_kd_ty (tyS,kdS,rkS) f,
                                    map (tysize (theta,omega,gamma) clause) Args)
                    end
                | NONE => Kzero ty
           end
           handle HOL_ERR _ =>
           if is_app_type ty then
                    let val (opr,args) = strip_app_type ty
                        val Kind = kind_of opr
                        val kind_args = fst(strip_arrow_kind Kind)
                        val opr_tm = tysize (theta,omega,gamma) clause opr
                        val (ubtys,oprty1) = strip_univ_type (type_of opr_tm)
                        val oprty0 = drop kind_args oprty1
                        val oprty = lose (length kind_args - length args) oprty0
                        val Thetas = Type.om_match_type oprty ty
                        val ubtys' = map (Type.inst_rk_kd_ty Thetas) ubtys
                        val opr_tm' = inst_rk_kd_ty Thetas opr_tm
                        val opr_tm'' = list_mk_tycomb (opr_tm', ubtys')
                        val arg_tms = map (tysize (theta,omega,gamma) clause) args
                    in list_match_mk_comb(opr_tm'', arg_tms)
                    end
           else if is_abs_type ty then
                    let val (bvar,body) = dest_abs_type ty
                        val bvar_tm = genvar (bvar --> numSyntax.num)
                        val theta' = (fn ty => if ty = bvar then SOME bvar_tm else theta ty)
                        val body_tm = tysize (theta',omega,gamma) clause body
                    in mk_abs(bvar_tm, body_tm)
                    end
           else if is_univ_type ty then Kzero ty
           else if is_exist_type ty then Kzero ty
           else raise ERR "tysize" "impossible type"
end;

fun dupls [] (C,D) = (rev C, rev D)
  | dupls (h::t) (C,D) = dupls t (if op_mem eq h t then (C,h::D) else (h::C,D));

fun crunch [] = []
  | crunch ((x,y)::t) =
    let val key = #1(dom_rng(type_of x))
        val (yes,no) = partition (fn(x,_) => (#1(dom_rng(type_of x))=key)) t
    in (key, (x,y)::yes)::crunch no
    end;

local open arithmeticTheory
      val zero_rws = [Rewrite.ONCE_REWRITE_RULE [ADD_SYM] ADD_0, ADD_0]
      val Zero  = numSyntax.zero_tm
      val One   = numSyntax.term_of_int 1
in
fun define_size_rk ax rec_fn db =
 let val dtys = Prim_rec.doms_of_tyaxiom ax  (* primary types in axiom *)
     val tyvars = Lib.U (map (snd o dest_type) dtys)
     val (_, abody) = strip_forall(concl ax)
     val (exvs, ebody) = strip_exists abody
     (* list of all constructors with arguments *)
     val conjl = strip_conj ebody
     val bare_conjl = map (snd o strip_forall) conjl
     val capplist = map (rand o lhs) bare_conjl
     val def_name = fst(dest_type(type_of(hd capplist)))
     (* 'a -> num variables : size functions for type variables *)
     val fparams = rev(fst(rev_itlist mk_tyvar_size tyvars
                             ([],free_varsl capplist)))
     val fparams_tyl = map type_of fparams
     fun proto_const n ty =
         mk_var(n, itlist (curry op-->) fparams_tyl (ty --> num))
     fun tyop_binding ty =
       let val {Tyop=root_tyop,Thy=root_thy,...} = dest_thy_type ty
       in ((root_thy,root_tyop), (ty, proto_const(root_tyop^"_size") ty))
       end
     val tyvar_map = zip tyvars fparams
     val tyop_map = map tyop_binding dtys
     fun theta tyv =
          case assoc1 tyv tyvar_map
           of SOME(_,f) => SOME f
            | NONE => NONE
     val type_size_env = tysize_env db
     fun gamma str =
          case assoc1 str tyop_map
           of NONE  => type_size_env str
            | SOME(_,(_, v)) => SOME v
     (* now the ugly nested map *)
     val head_of_clause = head o lhs o snd o strip_forall
     fun is_dty M = mem(#1(dom_rng(type_of(head_of_clause M)))) dtys
     val (dty_clauses,non_dty_clauses) = partition is_dty bare_conjl
     val dty_fns = fst(dupls (map head_of_clause dty_clauses) ([],[]))
     fun dty_size ty =
        let val (d,r) = dom_rng ty
        in list_mk_comb(proto_const(fst(dest_type d)^"_size") d,fparams)
        end
     val dty_map = zip dty_fns (map (dty_size o type_of) dty_fns)
     val non_dty_fns = fst(dupls (map head_of_clause non_dty_clauses) ([],[]))
     fun nested_binding (n,f) =
        let val name = String.concat[def_name,Lib.int_to_string n,"_size"]
            val (d,r) = dom_rng (type_of f)
            val proto_const = proto_const name d
        in (f, list_mk_comb (proto_const,fparams))
       end
     val nested_map0 = map nested_binding (enumerate 1 non_dty_fns)
     val nested_map1 = crunch nested_map0
     fun omega ty = assoc1 ty nested_map1
     val sizer = tysize(theta,omega,gamma)
     fun mk_app cl v = mk_comb(sizer cl (type_of v), v)
     val fn_i_map = dty_map @ nested_map0
     fun clause cl =
         let val (fn_i, capp) = dest_comb (lhs cl)
         in
         mk_eq(mk_comb(op_assoc eq fn_i fn_i_map, capp),
               case snd(strip_comb capp)
                of [] => Zero
                 | L  => end_itlist (curry numSyntax.mk_plus)
                                    (One::map (mk_app cl) L))
         end
     val pre_defn0 = list_mk_conj (map clause bare_conjl)
     val pre_defn1 = rhs(concl   (* remove zero additions *)
                      ((DEPTH_CONV BETA_CONV THENC
                        Rewrite.PURE_REWRITE_CONV zero_rws) pre_defn0))
                     handle UNCHANGED => pre_defn0
     val defn = new_recursive_definition_rk
                 {name=def_name^"_size_def",
                  rec_axiom=ax, rec_axiom_rk=rec_fn, def=pre_defn1}
     val cty = (I##(type_of o last)) o strip_comb o lhs o snd o strip_forall
     val ctyl = Lib.op_mk_set (pair_cmp eq equal) (map cty (strip_conj (concl defn)))
     val const_tyl = filter (fn (c,ty) => mem ty dtys) ctyl
     val const_tyopl = map (fn (c,ty) => (c,tyconst_names ty)) const_tyl
 in
    SOME {def=defn,const_tyopl=const_tyopl}
 end
 handle HOL_ERR _ => NONE

 fun define_size ax db = define_size_rk ax (fn _ => ax) db
end;

end
