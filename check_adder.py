import re
import numpy as np
import math
import sys

def bits_to_f16(bits: str) -> np.float16:
    return np.uint16(int(bits, 2)).view(np.float16)

def f16_to_bits(x: np.float16) -> str:
    return format(np.uint16(x.view(np.uint16)), "016b")

def ref_flag_add(ina_bits: str, inb_bits: str, sum_bits: str) -> str:
    a = bits_to_f16(ina_bits)
    b = bits_to_f16(inb_bits)
    s = bits_to_f16(sum_bits)

    # NaN in inputs
    if np.isnan(a) or np.isnan(b):
        return "11"

    # inf - inf (invalid)
    if np.isinf(a) and np.isinf(b) and (np.sign(a) != np.sign(b)):
        return "11"

    # NaN in result
    if np.isnan(s):
        return "11"

    # Overflow → ±Inf
    if np.isinf(s):
        return "01" if s > 0 else "10"

    # True underflow: the true result was nonzero but FP16 flushed it to ±0
    true_val = float(a) + float(b)

    if s == 0 and true_val != 0.0:
        # sign of the zero result determines flag
        return "10" if math.copysign(1.0, true_val) < 0 else "01"


    # Normal / no exception
    return "00"

def parse_cases(text: str):
    pattern = re.compile(
        r"In1\s*=\s*([01]{16}).*?"
        r"In2\s*=\s*([01]{16}).*?"
        r"Output\s*=\s*([01]{16}).*?"
        r"Exceptions\s*=\s*([01]{2}).*?"
        r"Expect\s*=\s*([01]{16})",
        re.S
    )
    cases = []
    for m in pattern.finditer(text):
        ina  = m.group(1)
        inb  = m.group(2)
        out  = m.group(3)
        flag = m.group(4)
        exp  = m.group(5)
        cases.append({
            "ina": ina,
            "inb": inb,
            "out": out,
            "expected": exp,
            "flag": flag
        })
    return cases

def equal_within_ulp(dut_bits: str, ref_bits: str, max_ulp: int = 1) -> bool:
    """Treat two half-precision values as equal if |code_dut - code_ref| <= max_ulp."""
    if dut_bits == ref_bits:
        return True
    du = int(dut_bits, 2)
    ru = int(ref_bits, 2)

    # If signs differ, don't soften equality; require exact match.
    sign_d = (du >> 15) & 1
    sign_r = (ru >> 15) & 1
    if sign_d != sign_r:
        return False

    return abs(du - ru) <= max_ulp

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 check_adder.py out.txt")
        return

    with open(sys.argv[1], "r") as f:
        text = f.read()

    cases = parse_cases(text)

    wrong_out_vs_expected = 0
    wrong_out_vs_ref = 0
    wrong_flag_vs_ref = 0

    for i, c in enumerate(cases, 1):
        A    = c["ina"]
        B    = c["inb"]
        OUT  = c["out"]
        EXP  = c["expected"]
        FLAG = c["flag"]

        # reference sum in half-precision
        ref_sum_bits = f16_to_bits(bits_to_f16(A) + bits_to_f16(B))
        ref_f        = ref_flag_add(A, B, ref_sum_bits)

        # Only consider output mismatches for non-exceptional cases
        count_output = (ref_f == "00")

        if count_output:
            out_ne_exp = not equal_within_ulp(OUT, EXP, max_ulp=1)
            out_ne_ref = not equal_within_ulp(OUT, ref_sum_bits, max_ulp=1)
        else:
            out_ne_exp = False
            out_ne_ref = False

        flag_ne_ref = (FLAG != ref_f)

        if out_ne_exp:
            wrong_out_vs_expected += 1
        if out_ne_ref:
            wrong_out_vs_ref += 1
        if flag_ne_ref:
            wrong_flag_vs_ref += 1

        print(f"Case {i}:")
        print(f"  In1        : {A}")
        print(f"  In2        : {B}")
        print(f"  Expected   : {EXP}")
        print(f"  DUT Output : {OUT}")
        print(f"  Ref Output : {ref_sum_bits}")
        print(f"  DUT Flag   : {FLAG}")
        print(f"  Ref Flag   : {ref_f}")
        print(f"  (count_output={count_output})")
        print(f"  Out!=Exp   : {out_ne_exp}")
        print(f"  Out!=Ref   : {out_ne_ref}")
        print(f"  Flag!=Ref  : {flag_ne_ref}")
        print()

    print("========== SUMMARY ==========")
    print(f"Total cases                       : {len(cases)}")
    print(f"Output != Expected (normal only)  : {wrong_out_vs_expected}")
    print(f"Output != Reference (normal only) : {wrong_out_vs_ref}")
    print(f"Flag   != Reference               : {wrong_flag_vs_ref}")

if __name__ == "__main__":
    main()

