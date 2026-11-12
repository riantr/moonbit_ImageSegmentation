///|
/// Port of the `Watershed_Algorithm` ImageJ plugin (Christopher Mei, 2003),
/// an implementation of the watershed immersion algorithm of
/// Vincent and Soille, "Watersheds in digital spaces: an efficient algorithm
/// based on immersion simulations", IEEE PAMI 13(6), 583-598 (1991).
///
/// The pixels are sorted by gray level (a *stable* sort, so pixels of equal
/// level keep their raster order), the basins are flooded level by level and
/// the watershed lines are written into a new binary image.
priv struct Fifo {
  mut buf : Array[Int]
  mut head : Int
  mut tail : Int
  mut count : Int
}

///|
/// Create an empty FIFO queue.
fn fifo_new(capacity : Int) -> Fifo {
  {
    buf: Array::make(if capacity < 16 { 16 } else { capacity }, 0),
    head: 0,
    tail: 0,
    count: 0,
  }
}

///|
/// Java `WatershedFIFO.fifo_add(p)`: `LinkedList.addFirst`.
///
/// The Java queue adds at the head and removes at the tail, which is a
/// plain FIFO. The circular buffer therefore writes at `head` and reads at
/// `tail`.
fn fifo_add(q : Fifo, value : Int) -> Unit {
  if q.count == q.buf.length() {
    // grow: copy the live elements to the front of a bigger buffer
    let cap = q.buf.length() * 2
    let buf = Array::make(cap, 0)
    let mut i = 0
    while i < q.count {
      buf[i] = q.buf[(q.tail + i) % q.buf.length()]
      i = i + 1
    }
    q.buf = buf
    q.tail = 0
    q.head = q.count
  }
  q.buf[q.head] = value
  q.head = (q.head + 1) % q.buf.length()
  q.count = q.count + 1
}

///|
/// Java `WatershedFIFO.fifo_remove()`: `LinkedList.removeLast`.
fn fifo_remove(q : Fifo) -> Int {
  let value = q.buf[q.tail]
  q.tail = (q.tail + 1) % q.buf.length()
  q.count = q.count - 1
  value
}

///|
/// Java `WatershedFIFO.fifo_empty()`.
fn fifo_empty(q : Fifo) -> Bool {
  q.count == 0
}

///|
/// Label of a pixel that has not been visited yet (Java `INIT`).
pub const WS_INIT : Int = -1

///|
/// Label of a pixel that is a candidate of the current level (Java `MASK`).
pub const WS_MASK : Int = -2

///|
/// Label of a pixel that belongs to a watershed line (Java `WSHED`).
pub const WS_WSHED : Int = 0

///|
/// Label of the fictitious queue separator (Java `FICTITIOUS`).
pub const WS_FICTITIOUS : Int = -3

///|
/// Queue sentinel for the fictitious pixel: no real pixel can have this
/// index, so it can never be confused with one.
pub const WS_FICTITIOUS_INDEX : Int = -1

///|
/// Neighbour lists of every pixel, stored flat: the neighbours of pixel `p`
/// are `nbr_flat[p * 8 .. p * 8 + nbr_count[p]]`.
///
/// The order follows the Java `WatershedStructure`: E, NE, SE, W, NW, SW, N, S.
priv struct Neighbours {
  nbr_flat : Array[Int]
  nbr_count : Array[Int]
}

///|
/// Build the neighbour lists of the raster.
fn build_neighbours(width : Int, height : Int) -> Neighbours {
  let size = width * height
  let nbr_flat = Array::make(size * 8, 0)
  let nbr_count = Array::make(size, 0)
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      let idx = y * width + x
      let base = idx * 8
      let mut c = 0
      if x + 1 < width {
        nbr_flat[base + c] = idx + 1
        c = c + 1
        if y - 1 >= 0 {
          nbr_flat[base + c] = idx - width + 1
          c = c + 1
        }
        if y + 1 < height {
          nbr_flat[base + c] = idx + width + 1
          c = c + 1
        }
      }
      if x - 1 >= 0 {
        nbr_flat[base + c] = idx - 1
        c = c + 1
        if y - 1 >= 0 {
          nbr_flat[base + c] = idx - width - 1
          c = c + 1
        }
        if y + 1 < height {
          nbr_flat[base + c] = idx + width - 1
          c = c + 1
        }
      }
      if y - 1 >= 0 {
        nbr_flat[base + c] = idx - width
        c = c + 1
      }
      if y + 1 < height {
        nbr_flat[base + c] = idx + width
        c = c + 1
      }
      nbr_count[idx] = c
      x = x + 1
    }
    y = y + 1
  }
  { nbr_flat, nbr_count }
}

///|
/// Watershed segmentation of a grayscale image.
///
/// Returns the binary image in which the watershed lines are 255 and
/// everything else 0, exactly like the Java plugin's output image.
pub fn watershed(img : GrayImage) -> GrayImage {
  let width = img.width
  let height = img.height
  let size = width * height
  let pixels = img.pixels
  let nb = build_neighbours(width, height)
  let nbr_flat = nb.nbr_flat
  let nbr_count = nb.nbr_count
  let labels = Array::make(size, WS_INIT)
  let dists = Array::make(size, 0)
  // --- stable sort of the pixels by gray level ---
  // (Java uses Collections.sort, which is a stable merge sort)
  let order = Array::make(size, 0)
  let mut next = 0
  let mut level = 0
  while level < 256 {
    let mut i = 0
    while i < size {
      if pixels[i] == level {
        order[next] = i
        next = next + 1
      }
      i = i + 1
    }
    level = level + 1
  }
  // --- flooding ---
  let queue = fifo_new(size + 16)
  let mut curlab = 0
  let mut height_index1 = 0
  let mut height_index2 = 0
  let mut h = 0
  while h < 256 {
    // mask all pixels at level h
    let mut pixel_index = height_index1
    while pixel_index < size {
      let p = order[pixel_index]
      if pixels[p] != h {
        height_index1 = pixel_index
        break
      }
      labels[p] = WS_MASK
      let base = p * 8
      let mut i = 0
      while i < nbr_count[p] {
        let q = nbr_flat[base + i]
        if labels[q] >= 0 {
          dists[p] = 1
          fifo_add(queue, p)
          break
        }
        i = i + 1
      }
      pixel_index = pixel_index + 1
    }
    // extend the basins
    let mut curdist = 1
    fifo_add(queue, WS_FICTITIOUS_INDEX)
    let mut running = true
    while running {
      let mut p = fifo_remove(queue)
      if p == WS_FICTITIOUS_INDEX {
        if fifo_empty(queue) {
          running = false
        } else {
          fifo_add(queue, WS_FICTITIOUS_INDEX)
          curdist = curdist + 1
          p = fifo_remove(queue)
        }
      }
      if running {
        let base = p * 8
        let mut i = 0
        while i < nbr_count[p] {
          let q = nbr_flat[base + i]
          if dists[q] <= curdist && labels[q] >= 0 {
            if labels[q] > 0 {
              if labels[p] == WS_MASK {
                labels[p] = labels[q]
              } else if labels[p] != labels[q] {
                labels[p] = WS_WSHED
              }
            } else if labels[p] == WS_MASK {
              labels[p] = WS_WSHED
            }
          } else if labels[q] == WS_MASK && dists[q] == 0 {
            dists[q] = curdist + 1
            fifo_add(queue, q)
          }
          i = i + 1
        }
      }
    }
    // detect and process the new minima of level h
    let mut pixel_index2 = height_index2
    while pixel_index2 < size {
      let p = order[pixel_index2]
      if pixels[p] != h {
        height_index2 = pixel_index2
        break
      }
      dists[p] = 0
      if labels[p] == WS_MASK {
        curlab = curlab + 1
        labels[p] = curlab
        fifo_add(queue, p)
        while !fifo_empty(queue) {
          let q = fifo_remove(queue)
          let qbase = q * 8
          let mut i = 0
          while i < nbr_count[q] {
            let r = nbr_flat[qbase + i]
            if labels[r] == WS_MASK {
              labels[r] = curlab
              fifo_add(queue, r)
            }
            i = i + 1
          }
        }
      }
      pixel_index2 = pixel_index2 + 1
    }
    h = h + 1
  }
  // --- build the output image ---
  let out = GrayImage::new(width, height, 0)
  let mut i = 0
  while i < size {
    let p = order[i]
    if labels[p] == WS_WSHED {
      let base = p * 8
      let mut all_wshed = true
      let mut j = 0
      while j < nbr_count[p] {
        if labels[nbr_flat[base + j]] != WS_WSHED {
          all_wshed = false
          break
        }
        j = j + 1
      }
      if !all_wshed {
        out.pixels[p] = 255
      }
    }
    i = i + 1
  }
  out
}
