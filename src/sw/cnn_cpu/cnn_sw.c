#include "cnn_sw.h"
#include "cnn_params.h"   // generiert -> Gewichte/Bias/Requant
#include "cycles.h"

static int8_t requant_relu(int32_t acc, int32_t mult, uint8_t shift){
    int64_t t = (int64_t)acc * (int64_t)mult;
    if(shift) t += ((int64_t)1 << (shift-1));  // Runden (+0.5 LSB, wie relu_pool; nur shift!=0)
    int32_t r = (int32_t)(t >> shift);
    if(r < 0)   r = 0;                      // ReLU
    if(r > 127) r = 127;                    // saturieren auf int8-Aktivierung
    return (int8_t)r;
}

static void conv1_layer(const uint8_t *img, int8_t *out){        // 1x28x28 -> 8x26x26
    for(int oc=0; oc<8; oc++)
      for(int oy=0; oy<26; oy++)
        for(int ox=0; ox<26; ox++){
            int32_t acc = conv1_bias[oc];   // bias inkl. Zero-Point-Fold
            for(int ky=0; ky<3; ky++)
              for(int kx=0; kx<3; kx++)
                acc += (int32_t)img[(oy+ky)*28+(ox+kx)] * (int32_t)conv1_w[oc][ky][kx];
            out[(oc*26+oy)*26+ox] = requant_relu(acc, conv1_mult[oc], conv1_shift[oc]);
        }
}

static void conv2_layer(const int8_t *in, int8_t *out){          // 8x13x13 -> 16x11x11
    for(int oc=0; oc<16; oc++)
      for(int oy=0; oy<11; oy++)
        for(int ox=0; ox<11; ox++){
            int32_t acc = conv2_bias[oc];
            for(int ic=0; ic<8; ic++)
              for(int ky=0; ky<3; ky++)
                for(int kx=0; kx<3; kx++)
                    acc += (int32_t)in[(ic*13+(oy+ky))*13+(ox+kx)]
                         * (int32_t)conv2_w[oc][ic][ky][kx];
            out[(oc*11+oy)*11+ox] = requant_relu(acc, conv2_mult[oc], conv2_shift[oc]);
        }
}

static void maxpool2(const int8_t *in, int C, int IH, int IW, int8_t *out){
    int OH=IH/2, OW=IW/2;
    for(int c=0; c<C; c++)
      for(int oy=0; oy<OH; oy++)
        for(int ox=0; ox<OW; ox++){
            int8_t m = -128;
            for(int dy=0; dy<2; dy++)
              for(int dx=0; dx<2; dx++){
                int8_t v = in[(c*IH+(oy*2+dy))*IW+(ox*2+dx)];
                if(v > m) m = v;
              }
            out[(c*OH+oy)*OW+ox] = m;
        }
}

static void fc1_layer(const int8_t *in, int8_t *out){            // 400 -> 64
    for(int o=0; o<64; o++){
        int32_t acc = fc1_bias[o];
        for(int i=0; i<400; i++) acc += (int32_t)in[i]*(int32_t)fc1_w[o][i];
        out[o] = requant_relu(acc, fc1_mult[o], fc1_shift[o]);
    }
}

static void fc2_layer(const int8_t *in, int32_t *scores){       // 64 -> 10 (kein Requant)
    for(int o=0; o<10; o++){
        int32_t acc = fc2_bias[o];
        for(int i=0; i<64; i++) acc += (int32_t)in[i]*(int32_t)fc2_w[o][i];
        scores[o] = acc;
    }
}

static int argmax10(const int32_t *s){
    int best=0;
    for(int i=1;i<10;i++) if(s[i]>s[best]) best=i;
    return best;
}

int cnn_sw_infer(const uint8_t *img){
    static int8_t c1[8*26*26], p1[8*13*13], c2[16*11*11], p2[16*5*5], f1[64];
    int32_t scores[10];
    conv1_layer(img, c1);
    maxpool2(c1, 8, 26, 26, p1);
    conv2_layer(p1, c2);
    maxpool2(c2, 16, 11, 11, p2);
    fc1_layer(p2, f1);
    fc2_layer(f1, scores);
    return argmax10(scores);
}

int cnn_sw_infer_timed(const uint8_t *img, uint32_t lc[6]){
    static int8_t c1[8*26*26], p1[8*13*13], c2[16*11*11], p2[16*5*5], f1[64];
    int32_t scores[10]; uint32_t a,b;
    a=rdcycle(); conv1_layer(img,c1);       b=rdcycle(); lc[0]=b-a;
    a=rdcycle(); maxpool2(c1,8,26,26,p1);   b=rdcycle(); lc[1]=b-a;
    a=rdcycle(); conv2_layer(p1,c2);        b=rdcycle(); lc[2]=b-a;
    a=rdcycle(); maxpool2(c2,16,11,11,p2);  b=rdcycle(); lc[3]=b-a;
    a=rdcycle(); fc1_layer(p2,f1);          b=rdcycle(); lc[4]=b-a;
    a=rdcycle(); fc2_layer(f1,scores);
    int d=argmax10(scores);                 b=rdcycle(); lc[5]=b-a;
    return d;
}