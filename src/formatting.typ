#import "state.typ": num-state, group-state
#import "parsing.typ": *


#let sequence-constructor = $$.body.func()

/// Creates an equation from a sequence. This function leaves the
/// `block` attribute unset. 
#let make-equation(sequence) = {
  math.equation(sequence-constructor(sequence))
}

#assert.eq(make-equation((sym.minus, [2])).body, $-2$.body)



/// Formats a sign. If the sign is the ASCII character "-", the minus
/// unicode symbol "−" is returned. Otherwise, "+" is returned but only 
/// if `implicit-plus` is set to true. In all other cases, the result is
/// `none`. 
#let format-sign(sign, implicit-plus: false) = {
  if sign == "-" { return sym.minus }
  else if sign == "+" and implicit-plus { return sym.plus }
}

#assert.eq(format-sign("-", implicit-plus: false), sym.minus)
#assert.eq(format-sign("+", implicit-plus: false), none)
#assert.eq(format-sign("-", implicit-plus: true), sym.minus)
#assert.eq(format-sign("+", implicit-plus: true), sym.plus)
#assert.eq(format-sign(none, implicit-plus: true), none)



/// Inserts group separators (e.g., thousand separators if `group-size` is 3)
/// into a sequence of digits. 
/// - x (str): Input sequence. 
/// - invert (boolean): If `false`, the separators are inserted counting from
///   right-to-left (as customary for integers), if `true`, they are inserted
///   from left-to-right (for fractionals). 
#let insert-group-separators(
  x, 
  invert: false,
  threshold: 5,
  size: 3,
  sep: sym.space.thin
) = {
  if x.len() < threshold { return x }
  
  if not invert { x = x.rev() }
  let chunks = x.codepoints().chunks(size)
  if not invert { chunks = chunks.rev().map(array.rev) }
  return chunks.intersperse(sep).flatten().join()
}

#assert.eq(insert-group-separators("123"), "123")
#assert.eq(insert-group-separators("1234"), "1234")
#assert.eq(insert-group-separators("12345", sep: " "), "12 345")
#assert.eq(insert-group-separators("123456", sep: " "), "123 456")
#assert.eq(insert-group-separators("1234567", sep: " "), "1 234 567")
#assert.eq(insert-group-separators("12345678", sep: " "), "12 345 678")
#assert.eq(insert-group-separators("12345678", sep: " ", size: 2), "12 34 56 78")
#assert.eq(insert-group-separators("1234", sep: " ", threshold: 3), "1 234")

#assert.eq(insert-group-separators("1234", sep: " ", threshold: 3, invert: true), "123 4")
#assert.eq(insert-group-separators("1234567", sep: " ", threshold: 3, invert: true), "123 456 7")
#assert.eq(insert-group-separators("1234567", sep: " ", size: 2, threshold: 3, invert: true), "12 34 56 7")



#let contextual-group(x, invert: false) = {
  insert-group-separators(x, invert: invert, ..group-state.get())
}


/// Takes a sequence of digits and returns a new sequence of length `digits`. 
/// If the input sequence is too short, a corresponding number of trailing
/// zeros is appended. Exceeding inputs are truncated. 
#let fit-decimals(x, digits) = {
  let len = x.len()
  if len == digits or digits == auto { return x }
  if len < digits { return x + "0" * (digits - len) }
  if len > digits { return x.slice(0, digits) }
}

#assert.eq(fit-decimals("345", 3), "345")
#assert.eq(fit-decimals("345", 4), "3450")
#assert.eq(fit-decimals("345", 2), "34")




#let format-integer = it => {
  // int, group
  if it.group and it.int != none { it.int = contextual-group(it.int) }
  if it.int == "" { it.int = "0" }
  it.int
}



#let format-fractional = it => {
  // frac, group, digits, decimal-marker?
  let frac = fit-decimals(it.frac, it.digits)
  if frac.len() == 0 { return none }
  if it.group { frac = contextual-group(frac, invert: true) }
  it.decimal-marker + frac
}



#let format-comma-number = it => {
  // sign, int, frac, digits, group, implicit-plus
  let frac = format-fractional((frac: it.frac, group: it.group, digits: it.digits, decimal-marker: it.decimal-marker))
  
  return format-sign(it.sign, implicit-plus: it.implicit-plus) + format-integer((int: it.int, group: it.group)) + frac
}



#let format-uncertainty = it => {
  /// pm, digits, mode, concise, tight
  let pm = it.pm
  if pm == none { return () }
  let is-symmetric = type(pm.first()) != array
  if is-symmetric { pm = (pm,) }

  if it.concise {
    let compact-pm = (
      it.mode == "compact" or 
      (it.mode == "compact-marker" and pm.map(x => x.first().trim("0")).all(x => x.len() == 0))
    )
      
    if compact-pm {
      pm = pm.map(x => utility.shift-decimal-left(..x, -it.digits))
      it.digits = auto
    }
  }

  pm = pm.map(((int, frac)) => 
    format-comma-number((
      sign: none, int: int, frac: frac, digits: it.digits, group: false, implicit-plus: false, decimal-marker: it.decimal-marker
    ))
  )
  if is-symmetric {
    if it.concise { ("(", pm.first(), ")") }
    else {
      (
        math.class("normal", none),
        math.class(if it.tight {"normal"} else {"binary"}, sym.plus.minus),
        pm.first()
      )
    }
  } else {
     (
      math.attach(
        none, 
        t: sym.plus + pm.at(0), 
        b: sym.minus + pm.at(1)
      ),
    )
  }
}



#let format-power = it => {
  /// x, base, times, implicit-plus-exponent, tight, 
  if it.exponent == none { return () }
  
  let (sign, integer, fractional) = decompose-signed-float-string(it.exponent)
  let exponent = format-comma-number((sign: sign, int: integer, frac: fractional, digits: auto, group: false, implicit-plus: it.implicit-plus-exponent, decimal-marker: it.decimal-marker))

  let power = math.attach([#it.base], t: [#exponent])
  if it.times == none { (power,) }
  else {
    (
      box(),
      math.class(if it.tight {"normal"} else {"binary"}, it.times),
      power
    )
  }
}



#let show-num-impl = it => {
  /// sign, int, frac, e, pm, 
  /// digits
  /// omit-unit-mantissa, uncertainty-mode, implicit-plus
  
  let omit-mantissa = (
    it.omit-unit-mantissa and it.int == "1" and
    it.frac == "" and it.e != none and it.pm == none and it.digits == 0
  )

  let concise-uncertainty = it.uncertainty-mode != "separate"


  

  let integer = (
    sign: it.sign,
    int: if omit-mantissa { none } else { it.int },
    group: true,
    decimal-marker: it.decimal-marker
  )
  

  let uncertainty = (
    pm: it.pm,
    digits: it.digits,
    concise: concise-uncertainty,
    tight: it.tight,
    mode: it.uncertainty-mode,
    decimal-marker: it.decimal-marker
  )
  
  
  let power = (
    exponent: it.e, 
    base: it.base,
    times: if omit-mantissa {none} else {it.times},
    implicit-plus-exponent: it.implicit-plus-exponent,
    tight: it.tight,
    decimal-marker: it.decimal-marker
  )
  
  let integer-part = (
    format-sign(it.sign, implicit-plus: it.implicit-plus),
    format-integer(integer),
  )
  
  let fractional-part = (
    format-fractional((frac: it.frac, group: true, digits: it.digits, decimal-marker: it.decimal-marker)),
  )

  let uncertainty-part = format-uncertainty(uncertainty)

  if concise-uncertainty {
    fractional-part += uncertainty-part
    uncertainty-part = ()
  } 
  
  
  if it.pm != none and it.e != none and not concise-uncertainty {
    integer-part = ("(",) + integer-part
    uncertainty-part.push(")")
  }
  
  let result = (
    integer-part,
    fractional-part,
    uncertainty-part,
    format-power(power),
  )
  return result
}



