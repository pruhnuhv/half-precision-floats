import re
import numpy as np
import math
import sys

def bits_to_f16(bits: str) -> np.float16:
    return np.uint16(int(bits, 2)).view(np.float16)

def f16_to_bits(x: np.float16) -> str:
    return format(np.uint16(x.view(np.uint16)), "016b")

def ref_flag(ina_bits: str, inb_bits: str, prod_bits: str) -> str:
    a = bits_to_f16(ina_bits)
    b = bits_to_f16(inb_bits)
    p = bits_to_f16(prod_bits)

    # NaN or invalid op (inf * 0)
    if np.isnan(a) or np.isnan(b) or (np.isinf(a) and b == 0) or (np.isinf(b) and a == 0):
        return "11"
    if np.isnan(p):
        return "11"

    # Overflow → ±Inf
    if np.isinf(p):
        return "01" if p > 0 else "10"

    # Underflow to zero: nonzero operands, result zero
    if p == 0 and a != 0 and b != 0:
        return "01" if math.copysign(1.0, float(p)) > 0 else "10"

    # Normal / exact zero
    return "00"

def parse_cases(text: str):
    blocks = [b for b in text.strip().split("\n\n") if "InA" in b]
    cases = []
    for b in blocks:
        bits = re.findall(r"([01]{16})", b)
        fl = re.search(r"Flag\s*=\s*([01]{2})", b)
        if len(bits) != 4 or fl is None:
            continue
        cases.append({
            "ina": bits[0],
            "inb": bits[1],
            "expected": bits[2],
            "out": bits[3],
            "flag": fl.group(1)
        })
    return cases

def main():
    if len(sys.argv) < 2:
        print("Usage: python check_mult.py cases.txt")
        return

    with open(sys.argv[1], "r") as f:
        text = f.read()

    cases = parse_cases(text)

    wrong_out_vs_expected = 0
    wrong_out_vs_ref = 0
    wrong_flag_vs_ref = 0

    for i, c in enumerate(cases, 1):
        A = c["ina"]
        B = c["inb"]
        EXP = c["expected"]
        OUT = c["out"]
        FLAG = c["flag"]

        ref_prod_bits = f16_to_bits(bits_to_f16(A) * bits_to_f16(B))
        ref_f = ref_flag(A, B, ref_prod_bits)

        # only consider output mismatches if reference says "normal/zero" (00)
        count_output = (ref_f == "00")

        out_ne_exp = (OUT != EXP) if count_output else False
        out_ne_ref = (OUT != ref_prod_bits) if count_output else False
        flag_ne_ref = (FLAG != ref_f)

        if out_ne_exp:
            wrong_out_vs_expected += 1
        if out_ne_ref:
            wrong_out_vs_ref += 1
        if flag_ne_ref:
            wrong_flag_vs_ref += 1

        print(f"Case {i}:")
        print(f"  InA        : {A}")
        print(f"  InB        : {B}")
        print(f"  Expected   : {EXP}")
        print(f"  DUT Output : {OUT}")
        print(f"  Ref Output : {ref_prod_bits}")
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

