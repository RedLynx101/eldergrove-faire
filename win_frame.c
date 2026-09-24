// Eldergrove's frame effect: adapted from Bend's Linux window effect
// (bend2/effs/window_frame.c, Copyright HigherOrderCO, Apache License 2.0),
// with a parallel blit that fills each quadtree square at once instead of
// walking the tree per pixel.
#if defined(__linux__)
// Window
// ======

// An event is five words: kind (0 key, 1 mouse, 2 move, 3 close) and
// its fields; a frame answers the events pumped since the last one.


static Term pkwindow_node(Env e, const u32* ev) {
  static const u32 cids[3] = { CID_KEY, CID_MOUSE, CID_MOVE };
  if (ev[0] == 3) {
    return term_pak(CID_CLOSE, 0);
  }
  u32 n = ev[0] == 1 ? 4 : 2;
  Loc l = heap_alloc(e, cls_fit(n));
  for (u32 j = 0; j < n; j += 1) {
    e.mem[l + j] = ev[1 + j];
  }
  return term_ctr(cids[ev[0]], l);
}

static Term pkwindow_list(Env e, const u32* p, u64 n) {
  Term list = term_pak(CID_NIL, 0);
  for (u64 i = n; i > 0;) {
    i -= 1;
    Loc l = heap_alloc(e, 1);
    e.mem[l]     = io_seal(e, pkwindow_node(e, p + 5 * i), CID_CON);
    e.mem[l + 1] = io_seal(e, list, CID_CON);
    list = term_ctr(CID_CON, l);
  }
  return list;
}




#ifndef BendWin
#define BendWin BendWin
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

typedef struct {
  Display* dpy;
  Window   win;
  Atom     del;
  XImage*  img;
  u32      n;
  u32      cap;
  u32*     evs;
} BendWin;
#endif

// The Mac's key codes: a key's character in lower case, the function
// keys' private-use characters (the arrows at 63232), a modifier's
// 65536 + its key code.
static const u32 pkwindow_keys[][2] = {
  { XK_Escape,    27 },    { XK_Return,    13 },    { XK_KP_Enter,  13 },
  { XK_Tab,       9 },     { XK_BackSpace, 127 },   { XK_Up,        63232 },
  { XK_Down,      63233 }, { XK_Left,      63234 }, { XK_Right,     63235 },
  { XK_Insert,    63271 }, { XK_Delete,    63272 }, { XK_Home,      63273 },
  { XK_End,       63275 }, { XK_Page_Up,   63276 }, { XK_Page_Down, 63277 },
  { XK_Super_R,   65590 }, { XK_Super_L,   65591 }, { XK_Shift_L,   65592 },
  { XK_Caps_Lock, 65593 }, { XK_Alt_L,     65594 }, { XK_Control_L, 65595 },
  { XK_Shift_R,   65596 }, { XK_Alt_R,     65597 }, { XK_Control_R, 65598 },
};

static u32 pkwindow_key(XKeyEvent* ev) {
  char   c[8];
  KeySym ks = 0;
  ev->state &= ShiftMask | LockMask;
  int n = XLookupString(ev, c, sizeof c, &ks, NULL);
  for (u32 i = 0; i < sizeof pkwindow_keys / sizeof *pkwindow_keys; i += 1) {
    if (pkwindow_keys[i][0] == ks) {
      return pkwindow_keys[i][1];
    }
  }
  if (ks >= XK_F1 && ks <= XK_F12) {
    return 63236 + (u32)(ks - XK_F1);
  }
  if (n == 1 && (u8)c[0] >= 32) {
    return (u8)c[0] >= 'A' && (u8)c[0] <= 'Z' ? (u8)c[0] + 32 : (u8)c[0];
  }
  return 65536 + ev->keycode;
}

static void pkwindow_push(BendWin* win, u32 kind, u32 a, u32 b, u32 c, u32 d) {
  if (win->n == win->cap) {
    win->cap = win->cap == 0 ? 64 : win->cap * 2;
    win->evs = io_mem(realloc(win->evs, win->cap * 20));
  }
  u32 ev[5] = { kind, a, b, c, d };
  memcpy(win->evs + win->n * 5, ev, sizeof ev);
  win->n += 1;
}

static u32 pkwindow_clip(int v, u32 most) {
  return v < 0 ? 0 : (u32)v < most ? (u32)v : most - 1;
}

static void pkwindow_pump(BendWin* win) {
  u32 w = win->img->width;
  u32 h = win->img->height;
  while (XPending(win->dpy) > 0) {
    XEvent ev;
    XNextEvent(win->dpy, &ev);
    if (ev.type == KeyPress || ev.type == KeyRelease) {
      pkwindow_push(win, 0, pkwindow_key(&ev.xkey), ev.type == KeyPress, 0, 0);
    } else if (ev.type == ButtonPress || ev.type == ButtonRelease) {
      u32 b = ev.xbutton.button;
      if (b >= 1 && b <= 3) {
        pkwindow_push(win, 1, pkwindow_clip(ev.xbutton.x, w),
          pkwindow_clip(ev.xbutton.y, h), b == 1 ? 0 : 4 - b,
          ev.type == ButtonPress);
      }
    } else if (ev.type == MotionNotify) {
      pkwindow_push(win, 2, pkwindow_clip(ev.xmotion.x, w),
        pkwindow_clip(ev.xmotion.y, h), 0, 0);
    } else if (ev.type == ClientMessage
      && (Atom)ev.xclient.data.l[0] == win->del) {
      pkwindow_push(win, 3, 0, 0, 0, 0);
    }
  }
}


// The frame's pixels: window_dev on the device while the corpus is
// there (the tree's pages never leave it), else window_pix a pixel at
// a time.
static void pkfill_rec(Corpus H, Term t, u32 k, u32 x0, u32 y0, u32* pix,
  u32 w, u32 h) {
  if (x0 >= w || y0 >= h) {
    return;
  }
  if (term_tag(t) == TAG_CTR && k > 0) {
    Loc l = term_rfc(t) ? H[term_loc(t)] >> 24 : term_loc(t);
    u32 hs = 1u << (k - 1);
    pkfill_rec(H, H[l + 0], k - 1, x0, y0, pix, w, h);
    pkfill_rec(H, H[l + 1], k - 1, x0 + hs, y0, pix, w, h);
    pkfill_rec(H, H[l + 2], k - 1, x0, y0 + hs, pix, w, h);
    pkfill_rec(H, H[l + 3], k - 1, x0 + hs, y0 + hs, pix, w, h);
    return;
  }
  while (term_tag(t) == TAG_CTR) {
    Loc l = term_rfc(t) ? H[term_loc(t)] >> 24 : term_loc(t);
    t = H[l];
  }
  u32 c = (u32)term_loc(t) & 0xFFFFFF;
  u32 s = 1u << k;
  u32 x1 = x0 + s < w ? x0 + s : w;
  u32 y1 = y0 + s < h ? y0 + s : h;
  for (u32 y = y0; y < y1; y += 1) {
    u32* row = pix + (u64)y * w;
    for (u32 x = x0; x < x1; x += 1) {
      row[x] = c;
    }
  }
}

#include <pthread.h>

typedef struct {
  Corpus H;
  Term   t;
  u32    k, x0, y0, w, h;
  u32*   pix;
} PkJob;

static void* pkfill_job(void* arg) {
  PkJob* j = (PkJob*)arg;
  pkfill_rec(j->H, j->t, j->k, j->x0, j->y0, j->pix, j->w, j->h);
  return NULL;
}

// the 16 squares two levels down are filled on their own threads
static void pkwindow_fill(Corpus H, u32* pix, u32 w, u32 h, Term image, u32 k) {
  PkJob jobs[16];
  pthread_t th[16];
  u32 n = 0;
  Term top = image;
  if (term_tag(top) != TAG_CTR || k < 2) {
    pkfill_rec(H, image, k, 0, 0, pix, w, h);
    return;
  }
  Loc l = term_rfc(top) ? H[term_loc(top)] >> 24 : term_loc(top);
  u32 hs = 1u << (k - 1);
  for (u32 q = 0; q < 4; q += 1) {
    Term c = H[l + q];
    u32 cx = (q & 1) * hs;
    u32 cy = (q >> 1) * hs;
    if (term_tag(c) != TAG_CTR) {
      pkfill_rec(H, c, k - 1, cx, cy, pix, w, h);
      continue;
    }
    Loc m = term_rfc(c) ? H[term_loc(c)] >> 24 : term_loc(c);
    u32 qs = hs >> 1;
    for (u32 r = 0; r < 4; r += 1) {
      PkJob* j = &jobs[n];
      j->H = H; j->t = H[m + r]; j->k = k - 2;
      j->x0 = cx + (r & 1) * qs; j->y0 = cy + (r >> 1) * qs;
      j->w = w; j->h = h; j->pix = pix;
      pthread_create(&th[n], NULL, pkfill_job, j);
      n += 1;
    }
  }
  for (u32 i = 0; i < n; i += 1) {
    pthread_join(th[i], NULL);
  }
}

// A frame waits for the next 60 Hz tick, as the Mac's display sync.
static void pkwindow_pace(void) {
  static u64 due;
  static int off = -1;
  if (off < 0) {
    off = getenv("PARK_NOPACE") != NULL;
  }
  if (off) {
    return;
  }
  u64 now = io_tick();
  if (due > now) {
    struct timespec ts = { 0, (long)(due - now) };
    nanosleep(&ts, NULL);
  }
  due = (due > now ? due : now) + 16666667;
}

// The frame runs on a helper thread (io_work), so the event loop, and the
// worker pool, carry on with other computations -- the game computes its
// next frame while this one is filled, paced and shown. Only the helper
// touches X between the effect's start and its pack.
typedef struct {
  Corpus H;
  Term   image;
} PkArgs;

static void pkwindow_show(Corpus H, BendWin* win, Term image) {
  static u64 n, tf, tp, tx, last;
  u32 w = win->img->width;
  u32 h = win->img->height;
  u32 k = 0;
  while ((1u << k) < w || (1u << k) < h) {
    k += 1;
  }
  u64 t0 = io_tick();
  pkwindow_fill(H, (u32*)win->img->data, w, h, image, k);
  u64 t1 = io_tick();
  pkwindow_pace();
  u64 t2 = io_tick();
  XPutImage(win->dpy, win->win, DefaultGC(win->dpy, DefaultScreen(win->dpy)),
    win->img, 0, 0, 0, 0, w, h);
  XFlush(win->dpy);
  u64 t3 = io_tick();
  tf += t1 - t0; tp += t2 - t1; tx += t3 - t2;
  // PARK_DUMP=path: write the 300th frame's pixels as it was shown (PPM)
  static u64 shown;
  const char* dump = getenv("PARK_DUMP");
  if (dump && ++shown == 300) {
    FILE* fp = fopen(dump, "wb");
    if (fp) {
      fprintf(fp, "P6\n%u %u\n255\n", w, h);
      u32* px = (u32*)win->img->data;
      for (u64 i = 0; i < (u64)w * h; i += 1) {
        unsigned char rgb[3] = { (px[i] >> 16) & 255, (px[i] >> 8) & 255, px[i] & 255 };
        fwrite(rgb, 1, 3, fp);
      }
      fclose(fp);
    }
  }
  if (getenv("PARK_PROF") && ++n % 64 == 0) {
    fprintf(stderr, "fill %.1fms pace %.1fms put %.1fms frame %.1fms\n", tf / 64e6,
      tp / 64e6, tx / 64e6, (t3 - last) / 64e6);
    tf = tp = tx = 0; last = t3;
  }
}

static void pkframe_call(IoWork* w) {
  BendWin* win = (BendWin*)w->hand;
  PkArgs*  a   = (PkArgs*)w->data;
  pkwindow_pump(win);
  pkwindow_show(a->H, win, a->image);
}

static Term pkframe_pack(Env e, IoWork* w) {
  BendWin* win   = (BendWin*)w->hand;
  PkArgs*  a     = (PkArgs*)w->data;
  Term     image = a->image;
  Term     list  = pkwindow_list(e, win->evs, win->n);
  win->n = 0;
  free(a);
  w->data = NULL;
  return io_tup(e, io_hand(w->hand), io_tup(e, image, list));
}

#endif
Term win_frame_run(Env e, Term* f, IoWork* w) {
  io_sync();
  PkArgs* a = io_mem(malloc(sizeof *a));
  a->H     = e.mem;
  a->image = f[1];
  w->hand  = (intptr_t)io_hand_v(f[0]);
  w->data  = (char*)a;
  return io_work(w, pkframe_call, pkframe_pack);
}

static void __attribute__((constructor)) win_frame_use(void) {
  io_eff(CID_WIN_FRAME, win_frame_run, 0);
}
