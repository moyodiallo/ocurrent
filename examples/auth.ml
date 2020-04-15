(** Shows how to configure authentication and access control in the web interface.
    Run this and visit "/login" for configuration instructions. *)

let program_name = "auth"

module Git = Current_git
module Docker = Current_docker.Default

let pull = false
let timeout = Duration.of_min 50

let () = Logging.init ()

(* Run "docker build" on the latest commit in Git repository [repo]. *)
let pipeline ~repo () =
  let src = Git.Local.head_commit repo in
  let image = Docker.build ~pull ~timeout (`Git src) in
  Docker.run image ~args:["dune"; "exec"; "--"; "examples/docker_build_local.exe"; "--help"]

(* Access control policy. *)
let has_role user role =
  match user with
  | None -> role = `Viewer              (* Unauthenticated users can only look at things. *)
  | Some user ->
    match Current_web.User.id user, role with
    | "github:talex5", _ -> true        (* This user has all roles *)
    | _, (`Viewer | `Builder) -> true   (* Any GitHub user can cancel and rebuild *)
    | _ -> false

let main config mode repo auth =
  let repo = Git.Local.v (Fpath.v repo) in
  let engine = Current.Engine.create ~config (pipeline ~repo) in
  let authn = Option.map Current_github.Auth.make_login_uri auth in
  let site = Current_web.Site.v ?authn ~has_role ~name:program_name () in
  let routes =
    Routes.(s "login" /? nil @--> Current_github.Auth.login auth) ::
    Current_web.routes engine in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;
      Current_web.run ~mode ~site routes;
    ]
  end

(* Command-line parsing *)

open Cmdliner

let repo =
  Arg.value @@
  Arg.pos 0 Arg.dir (Sys.getcwd ()) @@
  Arg.info
    ~doc:"The directory containing the .git subdirectory."
    ~docv:"DIR"
    []

let cmd =
  let doc = "Build the head commit of a local Git repository using Docker." in
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner $ repo $ Current_github.Auth.cmdliner),
  Term.info program_name ~doc

let () = Term.(exit @@ eval cmd)