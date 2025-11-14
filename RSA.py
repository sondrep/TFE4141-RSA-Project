# High-level RSA algorithm
# Need to implement:
#   Encryption: C = M^e mod(n)
#   Decryption: M = C^d mod(n)
#   Where C is the encrypted message, M is the message,
#   n is p*q (product of prime numbers so that M < n) and e and d are public/private exponents

import math
from sympy import randprime
import secrets

M = secrets.randbits(256) # Original message
C = 0                     # Encrypted message

# Function for generating keys
def rsa_key_generation():
    p = randprime(2**127, 2**128)
    q = randprime(2**127, 2**128)
    n = p*q  
    phi_n = (p-1)*(q-1)
    e = 65537
    if math.gcd(e, phi_n) != 1:
        print("Check")
    d = pow(e, -1, phi_n)
    print("Phi(n):", phi_n)
    print("Public key:", e, n)
    print("Private key:", d, n)
    return e, d, n

###############################################
# This part will be implemented in VHDL

# Function for blakley multiplication
def blakley_mul(a, b, n):
    r = 0   
    for i in range(b.bit_length()-1, -1, -1):
        r = (r << 1) % n
        if (b >> i) & 1:
            r = (r + a) % n
    return r

# Function for doing modular exponentiation with blakley multiplication
def modexp_RL_method(base, exponent, n):
    
    # Init result, base, and exponent
    result = 1
    base = base % n
    e = exponent

    # Run blakley mul while exponent is greater than zero
    while e > 0:
        if e & 1:
            result = blakley_mul(result, base, n)
        base = blakley_mul(base, base, n)
        e = e >> 1
    return result

#
################################################

# Generate keys
e, d, n = rsa_key_generation()

# Encrypt message
C = modexp_RL_method(M, e, n)
print("Original message:", M)
print("Encrypted message:", C)

# Decrypt message
M_decrypted = modexp_RL_method(C, d, n)
print("Decrypted message:", M_decrypted)

# Check if decrypted message equals original message
if ((M % n) == M_decrypted):
    print("Success!")
else:
    print("Not success :(")