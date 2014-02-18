(*  OCamlPro Scilab Toolbox - AST manipulation utilities
 *  Copyright (C) 2013 - OCamlPro - Benjamin CANOU
 *
 *  This file must be used under the terms of the CeCILL.
 *  This source file is licensed as described in the file COPYING, which
 *  you should have received as part of this distribution.
 *  The terms are also available at
 *  http://www.cecill.info/licences/Licence_CeCILL_V2-en.txt *)

open ScilabAst

(** Instanciate this functor with the same {!Parameters} as the AST to
    obtain specialized utilities. *)
module Make
    (Parameters : Parameters)
    (Ast : module type of ScilabAst.Make (Parameters)) = struct
  open Ast

  (** This class defines a method [t] of type [t -> t] per AST type
      [t]. By default, the methods perform a deep copy, calling
      themselves recursively for composite nodes (except for functor
      Parameters which are preserved as is). This is useful to write
      local code transformations that affect a specific kind of nodes
      by only overriding the necessary method(s) and relying on the
      base class' default behaviour for other cases. *)
  class ast_mapper = object (self)
    method ast (stmts : ast) =
      List.map (self # stmt) stmts

    (** This method is called by the specific [t] methods for
        all types [t]. Overriding if will affect the mapping of all
        node kinds. For targeting only the descriptors of a specific
        kind of node [t], override its [t] method instead,
        removing the call to this method. *)
    method descr : 'a.'a descr -> 'a descr = fun descr ->
      let loc = self # loc descr.loc in
      let meta = self # meta descr.meta in
      let comment = List.map (fun c -> self # descr c) descr.comment in
      { descr with loc ; meta ; comment }

    method stmt ({ cstr } as stmt) =
      let stmt = self # descr stmt in
      { stmt with cstr = self # stmt_cstr cstr }

    method exp ({ cstr } as exp) =
      let exp = self # descr exp in
      { exp with cstr = self # exp_cstr cstr }

    method var ({ cstr } as var) =
      let var = self # descr var in
      { var with cstr = self # symbol cstr }

    method arg (name, exp) =
      (match name with None -> None | Some n -> Some (self # var n)),
      self # exp exp

    method matrix_contents ctns =
      let do_row ({ cstr } as descr) =
        let descr = self # descr descr in
        let cstr = List.map (self # exp) cstr in
        { descr with cstr }
      in
      List.map do_row ctns

    method stmt_cstr cstr =
      match cstr with
      | Assign (lefts, right) ->
        Assign (List.map (self # exp) lefts, self # exp right)
      | Seq stmts ->
        Seq (List.map (self # stmt) stmts)
      | Defun { name ; args ; rets ; body } ->
        Defun { name = self # var name ;
                args = List.map (self # var) args ;
                rets = List.map (self # var) rets ;
                body = self # stmt body }
      | Exp exp ->
        Exp (self # exp exp)
      | Break ->
        Break
      | Continue ->
        Continue
      | Comment text ->
        Comment (self # comment text)
      | For (it, range, body) ->
        For (self # var it, self # exp range, self # stmt body)
      | If (cond, tbody, Some fbody)  ->
        If (self # exp cond, self # stmt tbody, Some (self # stmt fbody)) 
      | If (cond, tbody, None)  ->
        If (self # exp cond, self # stmt tbody, None) 
      | Return  ->
        Return 
      | Select { cond ; cases ; default = None }  ->
        let cases = List.map (fun (e, s) -> self # exp e, self # stmt s) cases in
        Select { cond = self # exp cond ; cases ; default = None } 
      | Select { cond ; cases ; default = Some d }  ->
        let cases = List.map (fun (e, s) -> self # exp e, self # stmt s) cases in
        Select { cond = self # exp cond ; cases ; default = Some (self # stmt d) } 
      | Try (tbody, cbody)  ->
        Try (self # stmt tbody, self # stmt cbody) 
      | While (cond, tbody, Some fbody)  ->
        While (self # exp cond, self # stmt tbody, Some (self # stmt fbody)) 
      | While (cond, tbody, None)  ->
        While (self # exp cond, self # stmt tbody, None) 

    method exp_cstr cstr =
      match cstr with
      | Call (name, args, kind) ->
        Call (self # exp name, List.map (self # arg) args, kind)
      | Identity args ->
        Identity (List.map (self # exp) args)
      | Range (sexp, None, eexp) ->
        Range (self # exp sexp, None, self # exp eexp)
      | Range (sexp, Some stepexp, eexp) ->
        Range (self # exp sexp, Some (self # exp stepexp), self # exp eexp)
      | Var sym ->
        Var (self # var sym)
      | Matrix rows ->
        Matrix (self # matrix_contents rows)
      | Cell_array rows ->
        Cell_array (self # matrix_contents rows)
      | Unop (unop, exp) ->
        Unop (unop, self # exp exp)
      | Op (op, lexp, rexp) ->
        Op (op, self # exp lexp, self # exp rexp)
      | Bool _ | Num _ | String _ | Colon as e -> e
      | Error -> Error

    method unop (unop : unop) = unop
    method op (op : op) = op
    method comment (comment : string) = comment
    method loc (loc : Parameters.loc) = loc
    method meta (meta : Parameters.meta) = meta
    method symbol (symbol : Parameters.symbol) = symbol
  end

  (** This class defines a method [t] of type [t -> unit] per AST type
      [t]. By default, the methods perform a deep traversal, calling
      themselves recursively for composite nodes. This is useful to
      perform a specific treatment on nodes of a specific kind inside
      the AST by only overriding the necessary method(s) and relying
      on the base class' default behaviour for other cases. *)
  class ast_iterator = object (self)
    method ast (stmts : ast) =
      List.iter (self # stmt) stmts

    (** This method is called by the specific [t] methods for
        all types [t]. Overriding if will affect the iteration on all
        node kinds. For targeting only the descriptors of a specific
        kind of node [t], override its [t] method instead,
        removing the call to this method. *)
    method descr : 'a.'a descr -> unit = fun descr ->
      self # loc descr.loc ;
      self # meta descr.meta ;
      List.iter (self # descr) descr.comment

    method stmt ({ cstr } as stmt) =
      self # descr stmt ;
      self # stmt_cstr cstr

    method exp ({ cstr } as exp) =
      self # descr exp ;
      self # exp_cstr cstr

    method var ({ cstr } as var) =
      self # descr var ;
      self # symbol cstr

    method arg (name, exp) =
      (match name with None -> () | Some n -> self # var n) ;
      self # exp exp

    method matrix_contents ctns =
      let do_row ({ cstr } as descr) =
        self # descr descr ;
        List.iter (self # exp) cstr
      in
      List.iter do_row ctns

    method stmt_cstr cstr =
      match cstr with
      | Assign (lefts, right) ->
        List.iter (self # exp) lefts ;
        self # exp right
      | Seq stmts ->
        List.iter (self # stmt) stmts
      | Defun { name ; args ; rets ; body } ->
        self # var name ;
        List.iter (self # var) args ;
        List.iter (self # var) rets ;
        self # stmt body
      | Exp exp ->
        self # exp exp
      | Comment text ->
        self # comment text
      | For (it, range, body) ->
        self # var it ;
        self # exp range ;
        self # stmt body
      | If (cond, tbody, Some fbody)  ->
        self # exp cond ;
        self # stmt tbody ;
        self # stmt fbody
      | If (cond, tbody, None)  ->
        self # exp cond ;
        self # stmt tbody
      | Select { cond ; cases ; default = None }  ->
        List.iter (fun (e, s) -> self # exp e ; self # stmt s) cases ;
        self # exp cond
      | Select { cond ; cases ; default = Some d }  ->
        List.iter (fun (e, s) -> self # exp e ; self # stmt s) cases ;
        self # exp cond ;
        self # stmt d
      | Try (tbody, cbody)  ->
        self # stmt tbody ;
        self # stmt cbody
      | While (cond, tbody, Some fbody)  ->
        self # exp cond ;
        self # stmt tbody ;
        self # stmt fbody
      | While (cond, tbody, None)  ->
        self # exp cond ;
        self # stmt tbody
      | Return | Break | Continue -> ()

    method exp_cstr cstr =
      match cstr with
      | Call (name, args, kind) ->
        self # exp name ;
        List.iter (self # arg) args
      | Identity args ->
        List.iter (self # exp) args
      | Range (sexp, None, eexp) ->
        self # exp sexp ;
        self # exp eexp
      | Range (sexp, Some stepexp, eexp) ->
        self # exp sexp ;
        self # exp stepexp ;
        self # exp eexp
      | Var sym ->
        self # var sym
      | Matrix rows ->
        self # matrix_contents rows
      | Cell_array rows ->
        self # matrix_contents rows
      | Unop (unop, exp) ->
        self # exp exp
      | Op (op, lexp, rexp) ->
        self # exp lexp ;
        self # exp rexp
      | Bool _ | Num _ | String _ | Colon | Error -> ()

    method unop (unop : unop) = ()
    method op (op : op) = ()
    method comment (comment : string) = ()
    method loc (loc : Parameters.loc) = ()
    method meta (meta : Parameters.meta) = ()
    method symbol (symbol : Parameters.symbol) = ()
  end
end