# High-level RSA algorithm
# Need to implement:
#   Encryption: C = M^e mod(n)
#   Decryption: M = C^d mod(n)
#   Where C is the encrypted message, M is the message,
#   n is p*q (product of prime numbers so that M < n) and e and d are public/private exponents
import math

M = "Decrypted message"
C = 0

def find_coprime():
    return math.gcd == 1

def rsa_key_generation():
    p = 7
    q = 11
    n = p*q

    phi_n = (p-1)*(q-1)
