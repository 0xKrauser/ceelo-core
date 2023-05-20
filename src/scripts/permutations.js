function permute(permutation) {
  var length = permutation.length,
    result = [permutation.slice()],
    c = new Array(length).fill(0),
    i = 1,
    k,
    p

  while (i < length) {
    if (c[i] < i) {
      k = i % 2 && c[i]
      p = permutation[i]
      permutation[i] = permutation[k]
      permutation[k] = p
      ++c[i]
      i = 1
      result.push(permutation.slice())
    } else {
      c[i] = 0
      ++i
    }
  }
  return result
}

export default function getAllUniquePermsByTotal() {
  const data = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6]

  const combinations = []

  for (let i = 0; i < data.length - 2; i++) {
    for (let j = i + 1; j < data.length - 1; j++) {
      for (let k = j + 1; k < data.length; k++) {
        combinations.push([data[i], data[j], data[k]])
      }
    }
  }

  // returns all combinations with duplicates
  /*
  console.log('combinations')
  console.log(combinations)
  */

  const filtered = combinations.filter(((t = {}), (a) => !(t[a] = a in t)))

  // returns all unique permutations
  /*
  console.log('filtered')
  console.log(filtered)
  */

  // returns all combinations without duplicates
  const permutedFiltered = filtered.map((arr) => permute(arr)).flat(1)
  return permutedFiltered.filter(((t = {}), (a) => !(t[a] = a in t)))
}
