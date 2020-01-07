(*
 * Copyright (c) 2015 Gabriel Radanne <drupyog@zoho.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Rresult
open Astring

open Functoria_misc

module Key = Functoria_key
module Package = Functoria_package

type package = Package.t
let package = Package.v

module Info = struct
  type t = {
    name: string;
    output: string option;
    build_dir: Fpath.t;
    keys: Key.Set.t;
    context: Key.context;
    packages: package String.Map.t;
  }

  let name t = t.name
  let build_dir t = t.build_dir
  let output t = t.output
  let with_output t output = { t with output = Some output }

  let libraries ps =
    let libs p =
      if Package.build_dependency p
      then String.Set.empty
      else String.Set.of_list (Package.libraries p)
    in
    String.Set.elements
      (List.fold_left String.Set.union String.Set.empty
         (List.map libs ps))

  let packages t = List.map snd (String.Map.bindings t.packages)
  let libraries t = libraries (packages t)
  let package_names t = List.map Package.name (packages t)
  let pins t =
    List.fold_left
      (fun acc p -> match Package.pin p with
         | None -> acc
         | Some u -> (Package.name p, u) :: acc)
      [] (packages t)

  let keys t = Key.Set.elements t.keys
  let context t = t.context

  let create ~packages ~keys ~context ~name ~build_dir =
    let keys = Key.Set.of_list keys in
    let packages = List.fold_left (fun m p ->
        let n = Package.name p in
        match String.Map.find n m with
        | None -> String.Map.add n p m
        | Some p' -> match Package.merge p p' with
          | Some p -> String.Map.add n p m
          | None -> m
      ) String.Map.empty packages
    in
    { name; build_dir; keys; packages; context; output = None }

  let pp_packages ?(surround = "") ?sep ppf t =
    Fmt.pf ppf "%a" (Fmt.iter ?sep List.iter (Package.pp ~surround)) (packages t)

  let pp verbose ppf ({ name ; build_dir ; keys ; context ; output; _ } as t) =
    let show name = Fmt.pf ppf "@[<2>%s@ %a@]@," name in
    let list = Fmt.iter ~sep:(Fmt.unit ",@ ") List.iter Fmt.string in
    show "Name      " Fmt.string name;
    show "Build-dir " Fpath.pp build_dir;
    show "Keys      " (Key.pps context) keys;
    show "Output    " Fmt.(option string) output;
    if verbose then show "Libraries " list (libraries t);
    if verbose then
      show "Packages  "
        (pp_packages ?surround:None ~sep:(Fmt.unit ",@ ")) t

  let opam ?name ppf t =
    let name = match name with None -> t.name | Some x -> x in
    Fmt.pf ppf "opam-version: \"2.0\"@." ;
    Fmt.pf ppf "name: \"%s\"@." name ;
    Fmt.pf ppf "depends: [ @[<hv>%a@]@ ]@."
      (pp_packages ~surround:"\"" ~sep:(Fmt.unit "@ ")) t ;
    match pins t with
    | [] -> ()
    | pin_depends ->
      let pp_pin ppf (package, url) =
        Fmt.pf ppf "[\"%s.dev\" %S]" package url
      in
      Fmt.pf ppf "pin-depends: [ @[<hv>%a@]@ ]@."
        Fmt.(list ~sep:(unit "@ ") pp_pin) pin_depends
end

type _ typ =
  | Type: 'a -> 'a typ
  | Function: 'a typ * 'b typ -> ('a -> 'b) typ

let (@->) f t = Function (f, t)

let typ ty = Type ty

module rec Typ: sig

  type _ impl =
    | Impl: 'ty Typ.configurable -> 'ty impl (* base implementation *)
    | App: ('a, 'b) app -> 'b impl   (* functor application *)
    | If: bool Key.value * 'a impl * 'a impl -> 'a impl

  and ('a, 'b) app = {
    f: ('a -> 'b) impl;  (* functor *)
    x: 'a impl;          (* parameter *)
  }

  and abstract_impl = Abstract: _ impl -> abstract_impl

  class type ['ty] configurable = object
    method ty: 'ty typ
    method name: string
    method module_name: string
    method keys: Key.t list
    method packages: package list Key.value
    method connect: Info.t -> string -> string list -> string
    method configure: Info.t -> (unit, R.msg) R.t
    method build: Info.t -> (unit, R.msg) R.t
    method clean: Info.t -> (unit, R.msg) R.t
    method deps: abstract_impl list
  end

end = Typ

include Typ

let ($) f x = App { f; x }
let impl x = Impl x
let abstract x = Abstract x
let if_impl b x y = If(b,x,y)

let rec match_impl kv ~default = function
  | [] -> default
  | (f, i) :: t -> If (Key.(pure ((=) f) $ kv), i, match_impl kv ~default t)

class base_configurable = object
  method packages: package list Key.value = Key.pure []
  method keys: Key.t list = []
  method connect (_:Info.t) (_:string) l =
    Printf.sprintf "return (%s)" (String.concat ~sep:", " l)
  method configure (_: Info.t): (unit, R.msg) R.t = R.ok ()
  method build (_: Info.t): (unit, R.msg) R.t = R.ok ()
  method clean (_: Info.t): (unit, R.msg) R.t = R.ok ()
  method deps: abstract_impl list = []
end

class ['ty] foreign
     ?(packages=[]) ?(keys=[]) ?(deps=[]) module_name ty
  : ['ty] configurable
  =
  let name = Name.create module_name ~prefix:"f" in
  object
    method ty = ty
    method name = name
    method module_name = module_name
    method keys = keys
    method packages = Key.pure packages
    method connect _ modname args =
      Fmt.strf
        "@[%s.start@ %a@]"
        modname
        Fmt.(list ~sep:sp string)  args
    method clean _ = R.ok ()
    method configure _ = R.ok ()
    method build _ = R.ok ()
    method deps = deps
  end

let foreign ?packages ?keys ?deps module_name ty =
  Impl (new foreign ?packages ?keys ?deps module_name ty)

(* {Misc} *)

let rec equal
  : type t1 t2. t1 impl -> t2 impl -> bool
  = fun x y -> match x, y with
    | Impl c, Impl c' ->
      c#name = c'#name
      && List.for_all2 Key.equal c#keys c'#keys
      && List.for_all2 equal_any c#deps c'#deps
    | App a, App b -> equal a.f b.f && equal a.x b.x
    | If (cond1, t1, e1), If (cond2, t2, e2) ->
      (* Key.value is a functional value (it contains a closure for eval).
         There is no prettier way than physical equality. *)
      cond1 == cond2 && equal t1 t2 && equal e1 e2
    | Impl _, (If _ | App _)
    | App _ , (If _ | Impl _)
    | If _  , (App _ | Impl _) -> false

and equal_any (Abstract x) (Abstract y) = equal x y

let rec hash: type t . t impl -> int = function
  | Impl c ->
    Hashtbl.hash
      (c#name, Hashtbl.hash c#keys, List.map hash_any c#deps)
  | App { f; x } -> Hashtbl.hash (`Bla (hash f, hash x))
  | If (cond, t, e) ->
    Hashtbl.hash (`If (cond, hash t, hash e))

and hash_any (Abstract x) = hash x

module ImplTbl = Hashtbl.Make (struct
    type t = abstract_impl
    let hash = hash_any
    let equal = equal_any
  end)

let explode x = match x with
  | Impl c -> `Impl c
  | App { f; x } -> `App (Abstract f, Abstract x)
  | If (cond, x, y) -> `If (cond, x, y)

type key = Functoria_key.t
type context = Functoria_key.context
type 'a value = 'a Functoria_key.value

module type KEY =
  module type of Functoria_key
  with type 'a Arg.converter = 'a Functoria_key.Arg.converter
   and type 'a Arg.t = 'a Functoria_key.Arg.t
   and type Arg.info = Functoria_key.Arg.info
   and type 'a value = 'a Functoria_key.value
   and type 'a key = 'a Functoria_key.key
   and type t = Functoria_key.t
   and type Set.t = Functoria_key.Set.t
   and type 'a Alias.t = 'a Functoria_key.Alias.t
   and type context = Functoria_key.context

(** Devices *)

let src = Logs.Src.create "functoria" ~doc:"functoria library"
module Log = (val Logs.src_log src : Logs.LOG)

type job = JOB
let job = Type JOB

(* Noop, the job that does nothing. *)
let noop = impl @@ object
    inherit base_configurable
    method ty = job
    method name = "noop"
    method module_name = "Pervasives"
  end

(* Default argv *)
type argv = ARGV
let argv = Type ARGV

let sys_argv = impl @@ object
    inherit base_configurable
    method ty = argv
    method name = "argv"
    method module_name = "Sys"
    method !connect _info _m _ = "return Sys.argv"
  end


(* Keys *)

module Keys = struct

   let file = Fpath.(v (String.Ascii.lowercase Key.module_name) + "ml")

   let wrap f err =
     match f () with
     | Ok b -> b
     | Error _ -> R.error_msg err

   let with_output f k =
     wrap
       (Bos.OS.File.with_oc f k)
       ("couldn't open output channel " ^ Fpath.to_string f)

   let configure i =
     Log.info (fun m -> m "Generating: %a" Fpath.pp file);
     with_output file
       (fun oc () ->
          let fmt = Format.formatter_of_out_channel oc in
          Codegen.append fmt "(* %s *)" (Codegen.generated_header ());
          Codegen.newline fmt;
          let keys = Key.Set.of_list @@ Info.keys i in
          let pp_var k = Key.serialize (Info.context i) k in
          Fmt.pf fmt "@[<v>%a@]@." (Fmt.iter Key.Set.iter pp_var) keys;
          let runvars = Key.Set.elements (Key.filter_stage `Run keys) in
          let pp_runvar ppf v = Fmt.pf ppf "%s_t" (Key.ocaml_name v) in
          let pp_names ppf v = Fmt.pf ppf "%S" (Key.name v) in
          Codegen.append fmt "let runtime_keys = List.combine %a %a"
            Fmt.Dump.(list pp_runvar) runvars Fmt.Dump.(list pp_names) runvars;
          Codegen.newline fmt;
          R.ok ())

  let clean _i = Bos.OS.Path.delete file

  let name = "key"

end

let keys (argv: argv impl) = impl @@ object
    inherit base_configurable
    method ty = job
    method name = Keys.name
    method module_name = Key.module_name
    method !configure = Keys.configure
    method !clean = Keys.clean
    method !packages = Key.pure [package "functoria-runtime"]
    method !deps = [ abstract argv ]
    method !connect info modname = function
      | [ argv ] ->
        Fmt.strf
          "return (Functoria_runtime.with_argv (List.map fst %s.runtime_keys) %S %s)"
          modname (Info.name info) argv
      | _ -> failwith "The keys connect should receive exactly one argument."
  end

(* Module emiting a file containing all the build information. *)

type info = Info
let info = Type Info

let pp_libraries fmt l =
  Fmt.pf fmt "[@ %a]"
    Fmt.(iter ~sep:(unit ";@ ") List.iter @@ fmt "%S") l

let pp_packages fmt l =
  Fmt.pf fmt "[@ %a]"
    Fmt.(iter ~sep:(unit ";@ ") List.iter @@
         (fun fmt x -> pf fmt "%S, \"%%{%s:version}%%\"" x x)
        ) l

let pp_dump_pkgs module_name fmt (name, pkg, libs) =
  Fmt.pf fmt
    "%s.{@ name = %S;@ \
     @[<v 2>packages = %a@]@ ;@ @[<v 2>libraries = %a@]@ }"
    module_name name
    pp_packages (String.Set.elements pkg)
    pp_libraries (String.Set.elements libs)

let app_info ?(type_modname="Functoria_info")  ?(gen_modname="Info_gen") () =
  impl @@ object
    inherit base_configurable
    method ty = info
    method name = "info"
    val file = Fpath.(v (String.Ascii.lowercase gen_modname) + "ml")
    method module_name = gen_modname
    method !packages = Key.pure [package "functoria-runtime"]
    method !connect _ modname _ = Fmt.strf "return %s.info" modname

    method !clean _i =
      Bos.OS.Path.delete file >>= fun () ->
      Bos.OS.Path.delete Fpath.(file + "in")

    method !configure _i = Ok ()

    method !build i =
      Log.info (fun m -> m "Generating: %a" Fpath.pp file);
      (* this used to call 'opam list --rec ..', but that leads to
         non-reproducibility, since this uses the opam CUDF solver which
         drops some packages (which are in the repositories configured for the
         switch), see https://github.com/mirage/functoria/pull/189 for further
         discussion on this before changing the code below.  *)
      let rec opam_deps args collected =
        Log.debug (fun m -> m
                      "opam_deps %d args %d collected\nargs: %a\ncollected: %a"
                      (String.Set.cardinal args) (String.Set.cardinal collected)
                      (String.Set.pp ~sep:(Fmt.unit ",") Fmt.string) args
                      (String.Set.pp ~sep:(Fmt.unit ",") Fmt.string) collected);
        if String.Set.is_empty args then Ok collected
        else
          let pkgs = String.concat ~sep:"," (String.Set.elements args) in
          let cmd =
            Bos.Cmd.(v "opam" % "list" % "--installed" % "-s" % "--color=never" % "--depopts" % "--required-by" % pkgs)
          in
          (Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.out_lines) >>= fun (rdeps, _) ->
          let reqd = String.Set.of_list rdeps in
          let collected' = String.Set.union collected reqd in
          opam_deps (String.Set.diff collected' collected) collected'
      in
      opam_deps (String.Set.of_list (Info.package_names i)) String.Set.empty >>= fun opam ->
      let ocl = String.Set.of_list (Info.libraries i)
      in
      Bos.OS.File.writef Fpath.(file + "in")
        "@[<v 2>let info = %a@]" (pp_dump_pkgs type_modname) (Info.name i, opam, ocl) >>= fun () ->
      Bos.OS.Cmd.run Bos.Cmd.(v "opam" % "config" % "subst" % p file)
  end
