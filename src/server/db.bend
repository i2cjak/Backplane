import Base

# SQLite, all strings: effects/db.js over bun:sqlite (the server runs on
# Bun), required lazily so a web or phone bundle never touches it. A handle
# is the text after "ok " in Db.open's answer. Params bind as text, or as an
# integer when one is "#<digits>"; a statement given more or fewer params
# than it has placeholders fails. Changes are the rows each statement itself
# changed (sqlite3_changes: rows its triggers write are not counted). Each
# handle is used by one call at a time; run, batch, script and query keep
# their statements prepared per handle.

# open (or create) the file in WAL mode, synchronous=NORMAL, a 5 s busy
# timeout: "ok <handle>" or "fail <why>"
def Db.open(path: String) -> IO(String):
  import "./effects/db.js"

# one or more statements with no params (DDL, BEGIN/COMMIT, PRAGMA):
# "ok" or "fail <why>"
def Db.exec(h: String, sql: String) -> IO(String):
  import "./effects/db.js"

# one statement with ?-params: "ok <changes>" or "fail <why>"
def Db.run(h: String, sql: String, params: List<&2, String>) -> IO(String):
  import "./effects/db.js"

# one statement run for each row of params, all in one transaction (a
# savepoint, rolled back on any error): "ok <changes>" or "fail <why>"
def Db.batch(h: String, sql: String, rows: List<&2, List<&2, String>>) -> IO(String):
  import "./effects/db.js"

# several statements, each item [sql, param, ...], all in one transaction
# (a savepoint, so also inside the caller's BEGIN; rolled back on any
# error); statements are kept prepared by their SQL text: "ok <changes>"
# or "fail <why>"
def Db.script(h: String, items: List<&2, List<&2, String>>) -> IO(String):
  import "./effects/db.js"

# at most limit rows, every column as text (NULL is ""); an error is one
# row ["\u0000fail", why]
def Db.query(h: String, sql: String, params: List<&2, String>, limit: U32) -> IO(List<&2, List<&2, String>>):
  import "./effects/db.js"

# "ok" or "fail <why>"; the handle is free again after
def Db.close(h: String) -> IO(String):
  import "./effects/db.js"
