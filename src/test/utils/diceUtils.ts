export const equals = (a, b) => {
  if (a === b) return true
  if (a == null || b == null) return false
  if (a.length !== b.length) return false

  let aSorted = [...a].sort((a, b) => a - b)
  let bSorted = [...b].sort((a, b) => a - b)

  for (var i = 0; i < a.length; ++i) {
    if (aSorted[i] !== bSorted[i]) return false
  }
  return true
}
