/*
 * Copyright(C) OmniTI, Inc. 2010
 * double_to_numeric - IEEE floating point formatting routines.
 *                     Derived from UNIX V7, Copyright(C) Caldera International Inc.
 *                     and borrowed from the Apache APR sources, rather modified though
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer in the documentation and/or other materials provided
 *       with the distribution.
 *     * Neither the name OmniTI Computer Consulting, Inc. nor the names
 *       of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Author: Theo Schlossnagle
 */

#include "postgres.h"
#include "funcapi.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include <math.h>
#define NDIG 40

Datum double_to_numeric(double arg);
Datum uint64_to_numeric(uint64_t arg);
Datum int64_to_numeric(int64_t arg);

Datum int64_to_numeric(int64_t arg) {
  /* 5 units of base 10000 is larger then 2^64 */
  Numeric dst;
  int16 *buf, *b2;
  int r = 0, i;
  dst = palloc(NUMERIC_HDRSZ + 5 * sizeof(int16));
  buf = (int16 *)dst->n_data;
  b2 = &buf[4];
  dst->n_sign_dscale = NUMERIC_POS;
  if(arg < 0) {
    dst->n_sign_dscale = NUMERIC_NEG;
    arg = -arg;
  }
  while(arg != 0) {
    *b2-- = arg % 10000;
    arg /= 10000;
    r++;
  }
  b2++;
  if(buf != b2) for(i=0;i<r;i++) buf[i] = b2[i];
  SET_VARSIZE(dst, NUMERIC_HDRSZ + r * sizeof(int16));
  if(r) r--;
  dst->n_weight = r;
  PG_RETURN_NUMERIC(dst);
}

Datum uint64_to_numeric(uint64_t arg) {
  /* 5 units of base 10000 is larger then 2^64 */
  Numeric dst;
  int16 *buf, *b2;
  int r = 0, i;
  dst = palloc(NUMERIC_HDRSZ + 5 * sizeof(int16));
  buf = (int16 *)dst->n_data;
  b2 = &buf[4];
  while(arg != 0) {
    *b2-- = arg % 10000;
    arg /= 10000;
    r++;
  }
  b2++;
  if(buf != b2) for(i=0;i<r;i++) buf[i] = b2[i];
  SET_VARSIZE(dst, NUMERIC_HDRSZ + r * sizeof(int16));
  dst->n_sign_dscale = NUMERIC_POS;
  if(r) r--;
  dst->n_weight = r;
  PG_RETURN_NUMERIC(dst);
}

Datum double_to_numeric(double arg) {
    Numeric dst;
    register int r1 = 0, r2;
    double fi, fj;
    register int16 *p, *p1;
    int ndigits = NDIG;
    int wscale = 0, dscale = 0;
    uint16_t sign;
    int16 *buf;

    dst = palloc(NUMERIC_HDRSZ + NDIG * sizeof(int16));
    buf = (int16 *)dst->n_data;
    if (ndigits >= NDIG - 1)
        ndigits = NDIG - 2;

    if(isnan(arg)) {
      sign = NUMERIC_NAN;
      SET_VARSIZE(dst, NUMERIC_HDRSZ);
      dst->n_sign_dscale = NUMERIC_NAN;
      PG_RETURN_NUMERIC(dst);
    }
    sign = NUMERIC_POS;
    r2 = 0;
    p = &buf[0];
    if (arg < 0) {
        sign = NUMERIC_NEG;
        arg = -arg;
    }
    arg = modf(arg, &fi);
    p1 = &buf[NDIG];
    /*
     * Do integer part
     */
    if (fi != 0) {
        p1 = &buf[NDIG];
        while (p1 > &buf[0] && fi != 0) {
            fj = modf(fi / 10000, &fi);
            *--p1 = (int16)((fj + 0.00003) * 10000);
            r2++;
        }
        while (p1 < &buf[NDIG])
            *p++ = *p1++;
    }
    else if (arg > 0) {
        while ((fj = arg * 10000) < 1) {
            arg = fj;
            r2--;
        }
    }
    p1 = &buf[ndigits];
    p1 += r2;
    if (p1 < &buf[0]) {
        wscale = -ndigits;
        dscale = r1;
        buf[0] = '\0';
        ndigits = 0;
        SET_VARSIZE(dst, NUMERIC_HDRSZ);
        dst->n_sign_dscale = sign | (dscale & NUMERIC_DSCALE_MASK);
        dst->n_weight = 0;
        PG_RETURN_NUMERIC(dst);
    }
    wscale = r2;
    while (arg != 0 && p <= p1 && p < &buf[NDIG]) {
        arg *= 10000;
        arg = modf(arg, &fj);
        *p++ = (int16) fj;
        r1++;
    }
    if (p1 >= &buf[NDIG]) {
        int len;
        buf[NDIG - 1] = '\0';
        p1 = &buf[NDIG-2];
        while(p1 >= buf && *p1 == '0') p1--;
        len = NUMERIC_HDRSZ + ((char *)p1 - (char *)buf);
        dscale = r1;
        dst->n_sign_dscale = sign | (dscale & NUMERIC_DSCALE_MASK);
        dst->n_weight = wscale-1;
        SET_VARSIZE(dst, len);
        PG_RETURN_NUMERIC(dst);
    }
    p = p1;
    *p1 += 5;
    while (*p1 > 9999) {
        *p1 = 0;
        if (p1 > buf)
            ++ * --p1;
        else {
            *p1 = 1;
            (wscale)++;
            if (p > buf)
                *p = 0;
            p++;
        }
    }
    *p = 0;
    while(p >= buf && *p == 0) p--;
    dscale = r1;
    dst->n_sign_dscale = sign | (dscale & NUMERIC_DSCALE_MASK);
    dst->n_weight = wscale-1;
    SET_VARSIZE(dst, NUMERIC_HDRSZ + ((char *)p - (char *)buf));
    PG_RETURN_NUMERIC(dst);
}

