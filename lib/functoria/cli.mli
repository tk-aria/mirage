(*
 * Copyright (c) 2013-2020 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2013-2020 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2015-2020 Gabriel Radanne <drupyog@zoho.com>
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

(** Command-line handling. *)

open Cmdliner

type 'a args = {
  context : 'a;
  config_file : Fpath.t;
  output : string option;
  dry_run : bool;
}
(** The type for global arguments. *)

val peek_args : ?with_setup:bool -> string array -> unit args
(** [peek_args ?with_setup argv] parses the global command-line arguments. If
    [with_setup] is set (by default it is), interprets [-v] and [--color] to
    set-up the terminal configuration as a side-effect. *)

val peek_output : string array -> string option
(** [peek_full_eval argv] reads the [--output] option from [argv]; the return
    value is [None] if option is absent in [argv]. *)

(** {1 Sub-commands} *)

type 'a configure_args = 'a args
(** The type for arguments of the [configure] sub-command. *)

type 'a build_args = 'a args
(** The type for arguments of the [build] sub-command. *)

type 'a clean_args = 'a args
(** The type for arguments of the [clean] sub-command. *)

type 'a help_args = 'a args
(** The type for arguments of the [help] sub-command. *)

type query_kind =
  [ `Name | `Packages | `Opam | `Install | `Files of [ `Configure | `Build ] ]

type 'a query_args = { args : 'a args; kind : query_kind }
(** The type for arguments of the [query] sub-command. *)

type 'a describe_args = {
  args : 'a args;
  dotcmd : string;
  dot : bool;
  eval : bool option;
}
(** The type for arguments of the [describe] sub-command. *)

val peek_full_eval : string array -> bool option
(** [peek_full_eval argv] reads the [--eval] option from [argv]; the return
    value is [None] if option is absent in [argv]. *)

(** A value of type [action] is the result of parsing command-line arguments
    using [parse_args]. *)
type 'a action =
  | Configure of 'a configure_args
  | Query of 'a query_args
  | Describe of 'a describe_args
  | Build of 'a build_args
  | Clean of 'a clean_args
  | Help of 'a help_args

val pp_action : 'a Fmt.t -> 'a action Fmt.t
(** [pp_action] is the pretty-printer for actions. *)

val args : 'a action -> 'a args
(** [args a] are [a]'s global arguments. *)

(** {1 Evalutation} *)

val eval :
  ?with_setup:bool ->
  ?help_ppf:Format.formatter ->
  ?err_ppf:Format.formatter ->
  name:string ->
  version:string ->
  configure:'a Term.t ->
  query:'a Term.t ->
  describe:'a Term.t ->
  build:'a Term.t ->
  clean:'a Term.t ->
  help:'a Term.t ->
  string array ->
  'a action Term.result
(** Parse the functoria command line. The arguments to [~configure],
    [~describe], etc., describe extra command-line arguments that should be
    accepted by the corresponding subcommands.

    There are no side effects, save for the printing of usage messages and other
    help when either the 'help' subcommand or no subcommand is specified. *)

(** {1 Argv Transformers} *)

type choice =
  [ `Configure
  | `Build
  | `Clean
  | `Query of query_kind option
  | `Describe
  | `Help ]
(** The type for sub-command choices. *)

val pp_choice : choice Fmt.t
(** [pp_choice] is a pretty-printer for choices. *)

val map_choice :
  (choice option -> choice option) -> string array -> string array
(** [map_choice f argv] is [argv] where the sub-command have been changed by
    applying [f]. Raise [Invalid_argument] if the sub-command names are
    ambiguous. *)
