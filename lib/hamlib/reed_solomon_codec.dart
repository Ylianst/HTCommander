/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// reed_solomon_codec.dart - Reed-Solomon encoding and decoding
//
// Ported from C# HamLib/ReedSolomonCodec.cs
//

import 'dart:typed_data';

import 'fx25.dart';

/// Reed-Solomon encoding and decoding operations.
class ReedSolomon {
  ReedSolomon._();

  /// Encode [data] with Reed-Solomon error correction, writing the check
  /// bytes into [bb].
  static void encode(ReedSolomonCodec rs, Uint8List data, Uint8List bb) {
    bb.fillRange(0, rs.nRoots, 0);

    for (int i = 0; i < rs.nn - rs.nRoots; i++) {
      final int feedback = rs.indexOf[data[i] ^ bb[0]];
      if (feedback != rs.nn) {
        // Feedback term is non-zero
        for (int j = 1; j < rs.nRoots; j++) {
          bb[j] ^= rs.alphaTo[rs.modNN(feedback + rs.genPoly[rs.nRoots - j])];
        }
      }

      // Shift
      bb.setRange(0, rs.nRoots - 1, bb.sublist(1, rs.nRoots));

      if (feedback != rs.nn) {
        bb[rs.nRoots - 1] = rs.alphaTo[rs.modNN(feedback + rs.genPoly[0])];
      } else {
        bb[rs.nRoots - 1] = 0;
      }
    }
  }

  /// Decode [data] with Reed-Solomon error correction, correcting it in place.
  ///
  /// Returns the number of errors corrected, or -1 if uncorrectable.
  static int decode(
    ReedSolomonCodec rs,
    Uint8List data,
    List<int>? erasPos,
    int noEras,
  ) {
    int degLambda, el;
    int i, j, r, k;
    int u, tmp, num1, num2, den, discrR;
    final Uint8List lambda = Uint8List(rs.nRoots + 1); // Error locator poly
    final Uint8List s = Uint8List(rs.nRoots); // Syndrome vector
    final Uint8List b = Uint8List(rs.nRoots + 1);
    final Uint8List t = Uint8List(rs.nRoots + 1);
    final Uint8List omega = Uint8List(rs.nRoots + 1); // Error evaluator poly
    final Uint8List root = Uint8List(rs.nRoots);
    final Uint8List reg = Uint8List(rs.nRoots + 1);
    final Uint8List loc = Uint8List(rs.nRoots);
    int synError, count;

    // Form the syndromes; i.e., evaluate data(x) at roots of g(x)
    for (i = 0; i < rs.nRoots; i++) {
      s[i] = data[0];
    }

    for (j = 1; j < rs.nn; j++) {
      for (i = 0; i < rs.nRoots; i++) {
        if (s[i] == 0) {
          s[i] = data[j];
        } else {
          s[i] =
              data[j] ^
              rs.alphaTo[rs.modNN(rs.indexOf[s[i]] + (rs.fcr + i) * rs.prim)];
        }
      }
    }

    // Convert syndromes to index form, checking for nonzero condition
    synError = 0;
    for (i = 0; i < rs.nRoots; i++) {
      synError |= s[i];
      s[i] = rs.indexOf[s[i]];
    }

    if (synError == 0) {
      // If syndrome is zero, data is OK (no errors)
      count = 0;
      return count;
    }

    lambda.fillRange(1, 1 + rs.nRoots, 0);
    lambda[0] = 1;

    if (noEras > 0) {
      // Init lambda to be the erasure locator polynomial
      lambda[1] = rs.alphaTo[rs.modNN(rs.prim * (rs.nn - 1 - erasPos![0]))];
      for (i = 1; i < noEras; i++) {
        u = rs.alphaTo[rs.modNN(rs.prim * (rs.nn - 1 - erasPos[i]))];
        for (j = i + 1; j > 0; j--) {
          tmp = rs.indexOf[lambda[j - 1]];
          if (tmp != rs.nn) {
            lambda[j] ^= rs.alphaTo[rs.modNN(u + tmp)];
          }
        }
      }
    }

    for (i = 0; i < rs.nRoots + 1; i++) {
      b[i] = rs.indexOf[lambda[i]];
    }

    // Begin Berlekamp-Massey algorithm to determine error locator polynomial
    r = noEras;
    el = noEras;
    while (++r <= rs.nRoots) {
      // Compute discrepancy at the r-th step
      discrR = 0;
      for (i = 0; i < r; i++) {
        if ((lambda[i] != 0) && (s[r - i - 1] != rs.nn)) {
          discrR ^= rs.alphaTo[rs.modNN(rs.indexOf[lambda[i]] + s[r - i - 1])];
        }
      }
      discrR = rs.indexOf[discrR];

      if (discrR == rs.nn) {
        // B(x) <-- x*B(x)
        b.setRange(1, 1 + rs.nRoots, b.sublist(0, rs.nRoots));
        b[0] = rs.nn;
      } else {
        // T(x) <-- lambda(x) - discr_r*x*b(x)
        t[0] = lambda[0];
        for (i = 0; i < rs.nRoots; i++) {
          if (b[i] != rs.nn) {
            t[i + 1] = lambda[i + 1] ^ rs.alphaTo[rs.modNN(discrR + b[i])];
          } else {
            t[i + 1] = lambda[i + 1];
          }
        }
        if (2 * el <= r + noEras - 1) {
          el = r + noEras - el;
          // B(x) <-- inv(discr_r) * lambda(x)
          for (i = 0; i <= rs.nRoots; i++) {
            b[i] = (lambda[i] == 0)
                ? rs.nn
                : rs.modNN(rs.indexOf[lambda[i]] - discrR + rs.nn);
          }
        } else {
          // B(x) <-- x*B(x)
          b.setRange(1, 1 + rs.nRoots, b.sublist(0, rs.nRoots));
          b[0] = rs.nn;
        }
        lambda.setRange(0, rs.nRoots + 1, t);
      }
    }

    // Convert lambda to index form and compute deg(lambda(x))
    degLambda = 0;
    for (i = 0; i < rs.nRoots + 1; i++) {
      lambda[i] = rs.indexOf[lambda[i]];
      if (lambda[i] != rs.nn) {
        degLambda = i;
      }
    }

    // Compute error evaluator polynomial omega(x) = s(x)*lambda(x)
    // (modulo x**NROOTS). Also find deg(omega)
    int degOmega = 0;
    for (i = 0; i < rs.nRoots; i++) {
      tmp = 0;
      for (j = (degLambda < i) ? degLambda : i; j >= 0; j--) {
        if ((s[i - j] != rs.nn) && (lambda[j] != rs.nn)) {
          tmp ^= rs.alphaTo[rs.modNN(s[i - j] + lambda[j])];
        }
      }
      if (tmp != 0) {
        degOmega = i;
      }
      omega[i] = rs.indexOf[tmp];
    }
    omega[rs.nRoots] = rs.nn;

    // Find roots of the error locator polynomial by Chien search
    reg.setRange(1, 1 + rs.nRoots, lambda.sublist(1, 1 + rs.nRoots));
    count = 0;
    k = rs.iPrim - 1;
    for (i = 1; i <= rs.nn; i++, k = rs.modNN(k + rs.iPrim)) {
      int q = 1;
      for (j = degLambda; j > 0; j--) {
        if (reg[j] != rs.nn) {
          reg[j] = rs.modNN(reg[j] + j);
          q ^= rs.alphaTo[reg[j]];
        }
      }
      if (q != 0) continue; // Not a root

      // Store root (index-form) and error location number
      root[count] = i;
      loc[count] = k;

      // If we've already found max possible roots, abort the search
      if (++count == degLambda) break;
    }

    if (degLambda != count) {
      // deg(lambda) unequal to number of roots => uncorrectable error detected
      count = -1;
      return count;
    }

    // Compute error values in poly-form. num1 = omega(inv(X(l))),
    // num2 = inv(X(l))**(FCR-1) and den = lambda_pr(inv(X(l))) all in poly-form
    for (j = count - 1; j >= 0; j--) {
      num1 = 0;
      for (i = degOmega; i >= 0; i--) {
        if (omega[i] != rs.nn) {
          num1 ^= rs.alphaTo[rs.modNN(omega[i] + i * root[j])];
        }
      }

      num2 = rs.alphaTo[rs.modNN(root[j] * (rs.fcr - 1) + rs.nn)];
      den = 0;

      // lambda[i+1] for i even is the formal derivative lambda_pr of lambda[i]
      for (
        i = (degLambda < (rs.nRoots - 1) ? degLambda : (rs.nRoots - 1)) & ~1;
        i >= 0;
        i -= 2
      ) {
        if (lambda[i + 1] != rs.nn) {
          den ^= rs.alphaTo[rs.modNN(lambda[i + 1] + i * root[j])];
        }
      }

      if (den == 0) {
        count = -1;
        return count;
      }

      // Apply error to data
      if (num1 != 0 && loc[j] < rs.nn) {
        data[loc[j]] ^=
            rs.alphaTo[rs.modNN(
              rs.indexOf[num1] + rs.indexOf[num2] + rs.nn - rs.indexOf[den],
            )];
      }
    }

    return count;
  }
}
