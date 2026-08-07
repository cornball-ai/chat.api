#' @title Matrix credential lifecycle
#' @description Where a Matrix client's credentials live, how they are
#'   read and written, and how they are refreshed. Split from
#'   \code{R/matrix.R} because it is a different concern: that file is
#'   about exchanging messages with a homeserver, this one is about
#'   having an account to do it with.

#' Load a Matrix configuration
#'
#' Reads the credentials an application saved, and returns them as a
#' \code{chat_config}: a list carrying the transport's own fields plus
#' whatever else the application stored alongside them, with the app
#' namespace and file path attached as attributes so
#' \code{\link{chat_config_save}} can write it back where it came from.
#'
#' @section Why the extra fields survive:
#' Applications keep their own settings in the same file -- which
#' accounts count as bots, who may open a private conversation, a
#' preferred model. Those are the application's, not the transport's,
#' and a loader that dropped them would make the file unreadable by its
#' owner. They pass through untouched and unvalidated.
#'
#' @param app Application namespace, e.g. \code{"corteza"}. Decides the
#'   default path under \code{tools::R_user_dir(app, "config")}.
#' @param path Explicit file path, overriding \code{app}'s default.
#' @param env_var Name of an environment variable that, when set,
#'   overrides both.
#' @return A list with class \code{chat_config}.
#' @examples
#' \dontrun{
#' cfg <- chat_matrix_config(app = "corteza",
#'                           env_var = "CORTEZA_MATRIX_CONFIG")
#' client <- chat_matrix(mx = cfg)
#' }
#' @export
chat_matrix_config <- function(app = NULL, path = NULL, env_var = NULL) {
    matrix_require_client("chat_matrix_config")
    args <- list(app = app)
    # Passed only when supplied. mx_client_load() distinguishes an
    # absent argument from a NULL one for path and env_var: an explicit
    # NULL path suppresses the app default rather than falling back to
    # it, which would look for the config in the working directory.
    if (!is.null(path)) {
        args$path <- path
    }
    if (!is.null(env_var)) {
        args$env_var <- env_var
    }
    cfg <- do.call(mx.client::mx_client_load, args)
    chat_config(cfg, app = app, path = attr(cfg, "path") %||% path)
}

#' Construct a chat_config
#'
#' @param x A named list of configuration fields.
#' @param app Application namespace the config belongs to, or NULL.
#' @param path File the config was read from, or NULL for one that has
#'   never been written.
#' @return A list with class \code{chat_config}.
#' @examples
#' chat_config(list(server = "https://ex.invalid", user = "bot"),
#'             app = "demo")
#' @export
chat_config <- function(x, app = NULL, path = NULL) {
    x <- unclass(x)
    stopifnot(is.list(x))
    # app and path travel as attributes rather than as fields, because a
    # field would collide with an application that already keeps one by
    # that name -- and be written back into the file as though it were
    # part of the credentials.
    attr(x, "app") <- app
    attr(x, "path") <- path
    structure(x, class = c("chat_config", "list"))
}

#' @export
print.chat_config <- function(x, ...) {
    # Never the values. A config holds an access token and often a
    # password, and printing one at a prompt is how it reaches a
    # terminal scrollback, a screenshot, or a pasted bug report.
    cat(sprintf("<chat_config> %s\n", attr(x, "path") %||% "(unsaved)"))
    cat(sprintf("  fields: %s\n", paste(sort(names(x)), collapse = ", ")))
    invisible(x)
}

#' Where a Matrix configuration lives
#'
#' @param app Application namespace.
#' @param env_var Name of an environment variable that overrides the
#'   default path, or NULL.
#' @param legacy Return the pre-\code{R_user_dir} location instead, for
#'   an application that needs to migrate an older file.
#' @return The file path (character).
#' @examples
#' chat_matrix_config_path("demo")
#' @export
chat_matrix_config_path <- function(app, env_var = NULL, legacy = FALSE) {
    matrix_require_client("chat_matrix_config_path")
    if (isTRUE(legacy)) {
        return(mx.client::mx_client_legacy_config_path(app))
    }
    if (is.null(env_var)) {
        mx.client::mx_client_config_path(app)
    } else {
        mx.client::mx_client_config_path(app, env_var = env_var)
    }
}

#' Persist a configuration
#'
#' Writes to the file the config came from, at mode 0600.
#'
#' @param config A \code{\link{chat_config}}, or a plain list together
#'   with \code{app}/\code{path}.
#' @param app Override the app namespace the config was loaded under.
#' @param path Override the file to write.
#' @return The config, invisibly.
#' @examples
#' \dontrun{
#' cfg$operators <- "@troy:example.org"
#' chat_config_save(cfg)
#' }
#' @export
chat_config_save <- function(config, app = NULL, path = NULL) {
    matrix_require_client("chat_config_save")
    app <- app %||% attr(config, "app")
    path <- path %||% attr(config, "path")
    if (is.null(app) && is.null(path)) {
        stop("chat_config_save(): nowhere to write. The config carries ",
             "neither an app nor a path, so pass one.", call. = FALSE)
    }
    args <- list(unclass_config(config))
    if (!is.null(app)) {
        args$app <- app
    }
    if (!is.null(path)) {
        args$path <- path
    }
    do.call(mx.client::mx_client_save, args)
    invisible(config)
}

# The plain list underneath, with the class and the bookkeeping
# attributes stripped. mx.client writes whatever it is handed, so an
# attribute left on here becomes a field in the file.
unclass_config <- function(config) {
    x <- unclass(config)
    attr(x, "app") <- NULL
    attr(x, "path") <- NULL
    x
}

#' Configure a Matrix account interactively
#'
#' Logs in to a homeserver, resolves the room, and writes the resulting
#' credentials.
#'
#' @param server Homeserver base URL.
#' @param user Localpart or full user id.
#' @param password Account password.
#' @param room Room id or alias to record as the default.
#' @param app Application namespace to save under.
#' @param path Explicit path to save to, overriding \code{app}.
#' @param device_id Device id to log in as. Reusing one keeps an
#'   existing E2EE identity; a new one starts a new device.
#' @param extra Named list of application fields to store alongside the
#'   credentials.
#' @return A \code{\link{chat_config}}, invisibly.
#' @examples
#' \dontrun{
#' cfg <- chat_matrix_configure(server = "https://matrix.example.org",
#'                              user = "bot", password = pw,
#'                              room = "#lab:example.org", app = "corteza")
#' }
#' @export
chat_matrix_configure <- function(server, user, password, room = NULL,
                                  app = NULL, path = NULL, device_id = NULL,
                                  extra = list()) {
    matrix_require_client("chat_matrix_configure")
    cfg <- mx.client::mx_client_configure(server = server, user = user,
        password = password, room = room, app = app, path = path,
        device_id = device_id, extra = extra)
    invisible(chat_config(cfg, app = app, path = attr(cfg, "path") %||% path))
}

#' @export
chat_relogin.chat_matrix <- function(client, ...) {
    refreshed <- mx.client::mx_client_relogin(client$env$mx)
    # Into the client, not back to the caller. A relogin that handed the
    # new credentials out and left the old ones in place would leave two
    # copies, and whichever the next call happened to use decides
    # whether it works.
    client$env$mx <- refreshed
    invisible(TRUE)
}

#' @export
chat_set_identity.chat_matrix <- function(client, display, ...) {
    fn <- client$identity_fn %||% mx.client::mx_set_displayname
    # The failure is held, not swallowed: the reload below has to run
    # either way, and the caller still has to hear that the rename did
    # not happen.
    #
    # mx_set_displayname() wraps itself in mx_with_relogin(), which
    # persists a refreshed config *before* retrying and then returns only
    # TRUE, discarding the client it refreshed. So a relogin whose retry
    # then failed -- rate limit, transient 5xx -- has still rotated the
    # token and still written it, and the live one is on disk while this
    # client holds the rejected one. Reloading only on success is exactly
    # how the next send goes out on a token the homeserver already
    # refused, and it fails silently, because nothing in this stack
    # relogins on a send.
    err <- NULL
    tryCatch(fn(client$env$mx, display), error = function(e) err <<- e)
    matrix_reload_into(client)
    if (!is.null(err)) {
        stop(err)
    }
    invisible(TRUE)
}

# Re-read the config from wherever this client's was loaded and adopt it.
# A client with no app and no path has nothing to re-read -- it was
# handed a config directly and nobody is persisting it -- and a read that
# fails leaves what we already had, which is no worse than not looking.
matrix_reload_into <- function(client) {
    path <- attr(client$env$mx, "path")
    app <- attr(client$env$mx, "app") %||% client$app
    if (is.null(path) && is.null(app)) {
        return(invisible(FALSE))
    }
    args <- list()
    if (!is.null(app)) {
        args$app <- app
    }
    if (!is.null(path)) {
        args$path <- path
    }
    fresh <- tryCatch(do.call(mx.client::mx_client_load, args),
                      error = function(e) NULL)
    if (is.null(fresh)) {
        return(invisible(FALSE))
    }
    client$env$mx <- fresh
    invisible(TRUE)
}
