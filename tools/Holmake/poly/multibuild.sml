structure multibuild =
struct

open ProcessMultiplexor HM_DepGraph Holmake_tools
type wp = HM_DepGraph.t workprovider

val W_EXITED = Posix.Process.W_EXITED

datatype buildresult =
         BR_OK
       | BR_ClineK of ((string * string list) * (OS.Process.status -> bool))
       | BR_Failed

fun extract_thypart s = (* <....>Theory.sml *)
  String.substring(s, 0, String.size s - 10)

fun nextchar #"|" = #"/"
  | nextchar #"/" = #"-"
  | nextchar #"-" = #"\\"
  | nextchar #"\\" = #"|"
  | nextchar c = c

fun stallstr "|" = "!"
  | stallstr ":" = "|"
  | stallstr "." = ":"
  | stallstr "!" = "!!"
  | stallstr "!!" = "!!!"
  | stallstr s = s

datatype monitor_status = MRunning of char
                        | Stalling of string * Time.time

infix ++
fun p1 ++ p2 = OS.Path.concat(p1, p2)
val loggingdir = ".hollogs"


val five_sec = Time.fromSeconds 5

fun statusString (MRunning c) = StringCvt.padRight #" " 3 (str c)
  | statusString (Stalling(s, _)) = StringCvt.padRight #" " 3 s

fun polish0 tag =
  if String.isSuffix "Theory.sml" tag orelse
     String.isSuffix "Theory.sig" tag
  then
    let
      val ss = Substring.full tag
      val (pfx,_) = Substring.position " " ss
      val thyname = Substring.slice(pfx,0,SOME(Substring.size pfx - 10))
    in
      Substring.string thyname
    end
  else tag

fun polish s = StringCvt.padRight #" " 17 (polish0 s)

fun graphbuild optinfo incinfo g =
  let
    val _ = OS.FileSys.mkDir loggingdir handle _ => ()
    val { build_command, mosml_build_command, warn, tgtfatal, diag,
          keep_going, quiet, hmenv, jobs, info } = optinfo
    val monitor_map = ref (Binarymap.mkDict String.compare)
    fun display_map () =
      (print "\r";
       Binarymap.app (fn (k,(_,v)) =>
                        print (polish k ^ statusString v))
                     (!monitor_map))
    fun monitor msg =
      case msg of
          StartJob (_, tag) =>
          let
            val safetag = String.map (fn #"/" => #"-" | c => c) tag
            val strm = TextIO.openOut (loggingdir ++ safetag)
          in
            monitor_map :=
              Binarymap.insert(!monitor_map, tag, (strm, MRunning #"|"));
            info ("\rStarting to build " ^ tag);
            display_map();
            NONE
          end
        | Output((_, tag), t, chan, msg) =>
          let
          in
            case Binarymap.peek(!monitor_map, tag) of
                NONE => (warn ("Lost monitor info for "^tag); NONE)
              | SOME (strm,stat) =>
                let
                  val stat' = case stat of MRunning c => MRunning (nextchar c)
                                         | Stalling _ => MRunning #"|"
                  val pfx = if chan = OUT then "" else "[ERR]"
                in
                  TextIO.output(strm,pfx ^ msg);
                  monitor_map :=
                    Binarymap.insert(!monitor_map, tag, (strm, stat'));
                  display_map();
                  NONE
                end
          end
        | NothingSeen((_, tag), {delay,...}) =>
          let
          in
            case Binarymap.peek(!monitor_map, tag) of
                NONE => (warn ("Lost monitor info for "^tag); NONE)
              | SOME (strm,stat) =>
                let
                  val stat' =
                      case stat of
                          MRunning c => if Time.>(delay, five_sec) then
                                          Stalling(".", delay)
                                        else MRunning c
                        | Stalling (s, sofar) =>
                          if Time.>(delay, Time.+(sofar, five_sec)) then
                            Stalling(stallstr s, delay)
                          else stat
                in
                  monitor_map :=
                    Binarymap.insert(!monitor_map, tag, (strm, stat'));
                  display_map();
                  NONE
                end
          end
        | Terminated((_, tag), st, _) =>
          let
          in
            case Binarymap.peek(!monitor_map, tag) of
                NONE => (warn ("Lost monitor info for "^tag); NONE)
              | SOME (strm,stat) =>
                let
                in
                  if st = W_EXITED then
                    info ("\r" ^ StringCvt.padRight #" " 75 tag ^ "OK")
                  else info ("\r" ^ StringCvt.padRight #" " 75 tag ^ "FAILED!");
                  TextIO.closeOut strm;
                  monitor_map := #1 (Binarymap.remove(!monitor_map, tag));
                  display_map();
                  if st = W_EXITED orelse keep_going then NONE
                  else SOME KillAll
                end
          end
        | _ => NONE

    fun genjob g =
      case find_runnable g of
          NONE => NoMoreJobs g
        | SOME (n,nI) =>
          let
            val _ = diag ("Found runnable node "^node_toString n)
            fun k b g =
              if b orelse keep_going then
                genjob (updnode(n, if b then Succeeded else Failed) g)
              else GiveUpAndDie g
            val depfs = map (toFile o #2) (#dependencies nI)
            val _ = #status nI = Pending orelse
                    raise Fail "runnable not pending"
            val target_s = String.concatWith " " (#target nI)
          in
            case #command nI of
                NoCmd => genjob (updnode (n,Succeeded) g)
              | SomeCmd c =>
                let
                  val hypargs as {noecho,ignore_error,command=c} =
                      process_hypat_options c
                  fun error b =
                    if b then Succeeded
                    else if ignore_error then
                      (warn ("Ignoring error building " ^ target_s);
                       Succeeded)
                    else Failed
                in
                  case mosml_build_command hmenv hypargs depfs of
                      SOME r => k (error (OS.Process.isSuccess r) = Succeeded) g
                    | NONE =>
                      let
                        fun update (g, b) = updnode (n, error b) g
                      in
                        NewJob ({tag = String.concatWith " " (#target nI),
                                 command = mk_shell_command c,
                                 update = update}, updnode(n, Running) g)
                      end
                end
              | BuiltInCmd =>
                let
                  fun bresk bres g =
                    case bres of
                        BR_OK => k true g
                      | BR_Failed => k false g
                      | BR_ClineK(cline, jobk) =>
                        let
                          fun b2res b = if b then OS.Process.success
                                        else OS.Process.failure
                          fun update (g, b) =
                            if jobk (b2res b) then
                              updnode(n, Succeeded) g
                            else
                              updnode(n, Failed) g
                        in
                          NewJob({tag = target_s,
                                  command = cline,
                                  update = update}, updnode(n, Running) g)
                        end
                  val bc = build_command incinfo
                  val _ = diag ("Handling builtin command for "^target_s)
                in
                  case #target nI of
                      [f] => (case toFile f of
                                  UI c => bresk (bc (Compile depfs) (SIG c)) g
                                | UO c => bresk (bc (Compile depfs) (SML c)) g
                                | _ => raise Fail ("bg tgt = " ^ f))
                    | [thyfile, _] =>
                      let
                        val thyname = extract_thypart thyfile
                      in
                        bresk (bc (BuildScript(thyname, depfs))
                                  (SML (Script thyname)))
                              g
                      end
                    | ts =>
                      raise Fail ("implicit bg targets: " ^
                                  String.concatWith ", " ts)
                end
          end
    val worklist =
        new_worklist {worklimit = jobs,
                      provider = { initial = g, genjob = genjob }}
  in
    do_work(worklist, monitor)
  end

end
