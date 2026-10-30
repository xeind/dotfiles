// Reports OpenCode's state to Rex as a program status (OSC 7501) through
// rex_program_status, so Rex shows it working, blocked or done.
const script = `${process.env.HOME}/.local/bin/rex_program_status`

export const RexStatus = async ({ $ }) => {
  if (!process.env.REX_BLOCK) return {}
  // OpenCode repeats busy while it works; send each change once, in order,
  // so a late "working" can't land after "done".
  let last = null
  let queue = Promise.resolve()
  const report = (state) => {
    if (state === last) return queue
    last = state
    queue = queue.then(() => $`${script} ${state}`.quiet().nothrow())
    return queue
  }
  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.status":
          if (event.properties?.status?.type === "busy") return report("working")
          break
        case "session.idle": return report("done")
        case "permission.asked": return report("permission")
        case "question.asked": return report("question")
        case "session.error": return report("error")
      }
    },
  }
}
