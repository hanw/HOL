signature History =
sig
  type 'a history

  exception CANT_BACKUP_ANYMORE

  val new_history : {obj:'a, limit:int} -> 'a history
  val apply       : ('a -> 'a) -> 'a history -> 'a history
  val set_limit   : 'a history -> int -> 'a history  
  val project     : ('a -> 'b) -> 'a history -> 'b
  val undo        : 'a history -> 'a history

end;
