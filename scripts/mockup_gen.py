#!/usr/bin/env python3
"""Generate faithful PNG mockups of the Jarvis app screens from the real theme colors."""
import cairosvg, os

BG="#0A0A0F"; SURF="#12121A"; CARD="#1A1A28"; BORDER="#2A2A3A"
PRIM="#6C63FF"; SEC="#00D4FF"; TXT="#FFFFFF"; TXT2="#8888AA"
OK="#00E676"; WARN="#FFB74D"; ERR="#FF5252"; PURP2="#9C27B0"

W,H=390,844
OUT="/home/user/Test1/mockups"
os.makedirs(OUT,exist_ok=True)

DEFS=f"""
<defs>
  <linearGradient id='gpc' x1='0' y1='0' x2='1' y2='1'>
    <stop offset='0' stop-color='{PRIM}'/><stop offset='1' stop-color='{SEC}'/>
  </linearGradient>
  <linearGradient id='gp' x1='0' y1='0' x2='1' y2='1'>
    <stop offset='0' stop-color='{PRIM}'/><stop offset='1' stop-color='{PURP2}'/>
  </linearGradient>
  <linearGradient id='gdark' x1='0' y1='0' x2='0' y2='1'>
    <stop offset='0' stop-color='{SURF}'/><stop offset='1' stop-color='{BG}'/>
  </linearGradient>
  <radialGradient id='glow' cx='0.5' cy='0.5' r='0.5'>
    <stop offset='0' stop-color='{PRIM}' stop-opacity='0.55'/>
    <stop offset='1' stop-color='{PRIM}' stop-opacity='0'/>
  </radialGradient>
  <filter id='soft' x='-50%' y='-50%' width='200%' height='200%'>
    <feGaussianBlur stdDeviation='6'/>
  </filter>
</defs>
"""

def frame(inner, bgfill="url(#gdark)"):
    return f"""<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' viewBox='0 0 {W} {H}'>
{DEFS}
<rect x='0' y='0' width='{W}' height='{H}' rx='0' fill='{bgfill}'/>
<!-- status bar -->
<text x='24' y='30' fill='{TXT}' font-family='Arial' font-size='13' font-weight='600'>9:41</text>
<g transform='translate(330,20)'>
  <rect x='0' y='2' width='18' height='10' rx='2' fill='none' stroke='{TXT}' stroke-width='1'/>
  <rect x='2' y='4' width='12' height='6' rx='1' fill='{TXT}'/>
  <rect x='19' y='5' width='2' height='4' rx='1' fill='{TXT}'/>
</g>
{inner}
</svg>"""

def rrect(x,y,w,h,r,fill,stroke=None,sw=1,op=1):
    s=f" stroke='{stroke}' stroke-width='{sw}'" if stroke else ""
    return f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='{r}' fill='{fill}' fill-opacity='{op}'{s}/>"

def txt(x,y,s,fill=TXT,size=14,weight='400',anchor='start',ls=0):
    return f"<text x='{x}' y='{y}' fill='{fill}' font-family='Arial,Helvetica,sans-serif' font-size='{size}' font-weight='{weight}' text-anchor='{anchor}' letter-spacing='{ls}'>{s}</text>"

def navbar(active):
    items=[("Chat","✉"),("Notes","✎"),("Goals","◎"),("Finance","€"),("Sport","⚡")]
    y=H-78
    out=[rrect(0,y,W,78,0,SURF,BORDER,1)]
    xs=[40,118,272,350]  # leave center for FAB
    labels=[("Chat",40),("Notes",118),("Goals",272),("Finance",350)]
    # we only have 4 side slots + center voice; map 5 screens: center is voice not a tab
    positions={"Chat":40,"Notes":118,"Goals":272,"Finance":350}
    for name,cx in positions.items():
        col=PRIM if name==active else TXT2
        out.append(f"<circle cx='{cx}' cy='{y+26}' r='4' fill='{col}'/>")
        out.append(txt(cx,y+52,name,col,10,'600' if name==active else '400','middle'))
    # center voice FAB
    out.append(f"<circle cx='195' cy='{y-6}' r='34' fill='url(#glow)'/>")
    out.append(f"<circle cx='195' cy='{y-6}' r='26' fill='url(#gp)'/>")
    out.append(txt(195,y+1,"\U0001F3A4",TXT,22,'400','middle'))
    return "".join(out)

def appbar(title,sub=None):
    out=[txt(24,64,title,TXT,24,'700',ls=0.5)]
    if sub:
        out.append(f"<circle cx='{26+len(title)*13}' cy='59' r='4' fill='{OK}'/>")
        out.append(txt(36+len(title)*13,64,sub,TXT2,12,'500'))
    return "".join(out)

# ---------------- LOGIN ----------------
def login():
    g=[]
    # dot grid
    for r in range(6,H-80,46):
        for c in range(20,W,46):
            g.append(f"<circle cx='{c}' cy='{r}' r='1' fill='{BORDER}' fill-opacity='0.6'/>")
    g.append(f"<circle cx='195' cy='250' r='90' fill='url(#glow)'/>")
    g.append(f"<circle cx='195' cy='250' r='52' fill='url(#gp)'/>")
    g.append(txt(195,272,"J",TXT,56,'800','middle'))
    g.append(txt(195,360,"JARVIS",TXT,34,'800','middle',6))
    g.append(txt(195,388,"Your Personal AI",TXT2,14,'500','middle',2))
    # password field
    g.append(rrect(40,470,310,52,12,SURF,BORDER,1))
    g.append(txt(60,502,"• • • • • • • •",TXT,18,'700'))
    g.append(txt(330,503,"\U0001F441",TXT2,16,'400','middle'))
    # connect button
    g.append(rrect(40,540,310,54,12,"url(#gpc)"))
    g.append(txt(195,574,"CONNECT",TXT,16,'700','middle',1.5))
    g.append(txt(195,628,"⚙  Advanced settings",TXT2,13,'500','middle'))
    return frame("".join(g),BG)

# ---------------- CHAT ----------------
def chat():
    g=[appbar("JARVIS","online")]
    # morning briefing card
    g.append(rrect(20,80,350,72,16,CARD,PRIM,1))
    g.append(f"<rect x='20' y='80' width='4' height='72' rx='2' fill='url(#gpc)'/>")
    g.append(txt(40,104,"☀  Morgen-Briefing",SEC,12,'700'))
    g.append(txt(40,126,"3 Termine heute · Sport-Ziel on track",TXT,13,'500'))
    g.append(txt(40,144,"Gestern 40€ über Budget — sparen?",TXT2,12,'400'))
    # jarvis bubble
    g.append(f"<circle cx='38' cy='190' r='16' fill='url(#gp)'/>")
    g.append(txt(38,196,"J",TXT,14,'700','middle'))
    g.append(rrect(62,176,250,46,14,CARD,BORDER,1))
    g.append(txt(78,204,"Guten Morgen! Hast du gut",TXT,13,'400'))
    g.append(txt(78,220,"geschlafen?",TXT,13,'400'))
    # user bubble
    g.append(rrect(180,236,170,40,14,"url(#gp)"))
    g.append(txt(330,261,"Ja, ziemlich gut \U0001F642",TXT,13,'500','end'))
    # jarvis bubble 2
    g.append(f"<circle cx='38' cy='312' r='16' fill='url(#gp)'/>")
    g.append(txt(38,318,"J",TXT,14,'700','middle'))
    g.append(rrect(62,296,260,46,14,CARD,BORDER,1))
    g.append(txt(78,324,"Schön! Hast du was geträumt?",TXT,13,'400'))
    g.append(txt(78,340,"Erzähl mir davon ✨",TXT2,12,'400'))
    # typing indicator
    g.append(rrect(62,356,70,34,14,CARD,BORDER,1))
    for i,cx in enumerate([84,97,110]):
        g.append(f"<circle cx='{cx}' cy='373' r='4' fill='{TXT2}' fill-opacity='{0.4+i*0.25}'/>")
    # quick suggestion chips
    g.append(rrect(20,560,120,30,15,SURF,BORDER,1)); g.append(txt(80,580,"Was steht an?",TXT2,11,'500','middle'))
    g.append(rrect(150,560,110,30,15,SURF,BORDER,1)); g.append(txt(205,580,"Neue Notiz",TXT2,11,'500','middle'))
    # input bar
    g.append(rrect(20,604,290,48,24,SURF,BORDER,1))
    g.append(txt(40,633,"Nachricht an Jarvis…",TXT2,13,'400'))
    g.append(f"<circle cx='340' cy='628' r='24' fill='url(#gpc)'/>")
    g.append(txt(340,634,"\U0001F3A4",TXT,18,'400','middle'))
    g.append(navbar("Chat"))
    return frame("".join(g))

# ---------------- NOTES ----------------
def notes():
    g=[appbar("Notes")]
    # search
    g.append(rrect(20,80,350,46,23,SURF,BORDER,1))
    g.append(txt(44,108,"\U0001F50D  Suche…",TXT2,13,'400'))
    # tag chips
    chips=[("All",True),("Ideen",False),("Arbeit",False),("Privat",False)]
    x=20
    for name,act in chips:
        wch=len(name)*8+24
        g.append(rrect(x,138,wch,28,14,PRIM if act else SURF,PRIM if act else BORDER,1,0.3 if act else 1))
        g.append(txt(x+wch/2,157,name,PRIM if act else TXT2,11,'600','middle'))
        x+=wch+10
    cards=[("Projekt Jarvis",PRIM,"Backend + App Phase 1\nfertigstellen",["dev"],True),
           ("Einkaufsliste",SEC,"Milch, Eier, Hafer-\nflocken, Obst",["privat"],False),
           ("Buch-Ideen",OK,"Notizen zu Atomic\nHabits Kapitel 3",["lesen"],False),
           ("Workout Plan",WARN,"Mo/Mi/Fr Push Pull\nLegs Split",["sport"],False)]
    px=[20,200]; py=[182,182+200]
    for i,(t,acc,prev,tags,pin) in enumerate(cards):
        x=px[i%2]; y=py[i//2]
        g.append(rrect(x,y,170,184,16,CARD,BORDER,1))
        g.append(f"<rect x='{x}' y='{y}' width='170' height='5' rx='2' fill='{acc}'/>")
        g.append(txt(x+16,y+34,t,TXT,14,'700'))
        if pin: g.append(txt(x+150,y+32,"\U0001F4CC",TXT,13,'400','middle'))
        for li,line in enumerate(prev.split("\n")):
            g.append(txt(x+16,y+58+li*18,line,TXT2,12,'400'))
        g.append(rrect(x+16,y+150,len(tags[0])*8+20,22,11,SURF,BORDER,1))
        g.append(txt(x+16+(len(tags[0])*8+20)/2,y+165,tags[0],TXT2,10,'500','middle'))
    # FAB
    g.append(f"<circle cx='330' cy='{H-120}' r='28' fill='url(#gpc)'/>")
    g.append(txt(330,H-112,"+",TXT,30,'400','middle'))
    g.append(navbar("Notes"))
    return frame("".join(g))

# ---------------- GOALS ----------------
def ring(cx,cy,r,pct,col,sw=8):
    import math
    c=2*math.pi*r
    return (f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='none' stroke='{BORDER}' stroke-width='{sw}'/>"
            f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='none' stroke='{col}' stroke-width='{sw}' "
            f"stroke-dasharray='{c}' stroke-dashoffset='{c*(1-pct)}' stroke-linecap='round' "
            f"transform='rotate(-90 {cx} {cy})'/>")
def goals():
    g=[appbar("Goals")]
    # stats card
    g.append(rrect(20,80,350,96,16,CARD,BORDER,1))
    g.append(ring(70,128,30,0.6,PRIM,7))
    g.append(txt(70,134,"60%",TXT,15,'700','middle'))
    g.append(txt(150,116,"3 aktive Ziele",TXT,15,'700'))
    g.append(txt(150,138,"2 diesen Monat geschafft",TXT2,12,'400'))
    g.append(txt(150,160,"\U0001F525 7 Tage Streak",WARN,13,'600'))
    data=[("1000€ sparen",0.72,OK,"On Track","28. Juni"),
          ("3x/Woche Sport",0.45,WARN,"At Risk","diese Woche"),
          ("Buch lesen",0.20,ERR,"Behind","30. Juni")]
    y=192
    for name,pct,col,status,dl in data:
        g.append(rrect(20,y,350,84,16,CARD,BORDER,1))
        g.append(txt(40,y+30,name,TXT,15,'700'))
        g.append(rrect(280,y+16,70,22,11,col,op=0.18))
        g.append(txt(315,y+31,status,col,10,'700','middle'))
        g.append(rrect(40,y+46,290,8,4,SURF,BORDER,1))
        g.append(rrect(40,y+46,int(290*pct),8,4,col))
        g.append(txt(40,y+72,f"{int(pct*100)}%  ·  bis {dl}",TXT2,11,'500'))
        y+=96
    g.append(f"<circle cx='330' cy='{H-120}' r='28' fill='url(#gpc)'/>")
    g.append(txt(330,H-112,"+",TXT,30,'400','middle'))
    g.append(navbar("Goals"))
    return frame("".join(g))

# ---------------- FINANCE ----------------
def finance():
    g=[appbar("Finance")]
    # balance card
    g.append(rrect(20,80,350,110,18,"url(#gp)"))
    g.append(txt(40,114,"Saldo diesen Monat",TXT,12,'500'))
    g.append(txt(40,154,"+ 1.340 €",TXT,34,'800'))
    g.append(txt(40,180,"↑ 15% mehr gespart als geplant",TXT,12,'600'))
    g.append(txt(345,118,"\U0001F4B0",TXT,22,'400','middle'))
    # bar chart income vs expense
    g.append(rrect(20,206,350,150,16,CARD,BORDER,1))
    g.append(txt(40,232,"Einnahmen vs. Ausgaben",TXT,13,'700'))
    bars=[("Mo",60,40),("Di",80,55),("Mi",45,70),("Do",90,50),("Fr",70,85),("Sa",40,60),("So",55,30)]
    bx=44
    for d,inc,exp in bars:
        g.append(rrect(bx,330-inc,14,inc,3,OK))
        g.append(rrect(bx+16,330-exp,14,exp,3,ERR))
        g.append(txt(bx+15,348,d,TXT2,9,'500','middle'))
        bx+=46
    # transactions
    tx=[("\U0001F355","Essen","Lidl Einkauf","-32,40 €",ERR),
        ("\U0001F4B5","Gehalt","Monatslohn","+2.100 €",OK),
        ("\U0001F697","Transport","Tankstelle","-58,00 €",ERR)]
    y=374
    for emo,cat,desc,amt,col in tx:
        g.append(rrect(20,y,350,56,14,CARD,BORDER,1))
        g.append(f"<circle cx='48' cy='{y+28}' r='18' fill='{SURF}'/>")
        g.append(txt(48,y+34,emo,TXT,16,'400','middle'))
        g.append(txt(78,y+25,cat,TXT,14,'600'))
        g.append(txt(78,y+43,desc,TXT2,11,'400'))
        g.append(txt(350,y+33,amt,col,14,'700','end'))
        y+=66
    g.append(f"<circle cx='330' cy='{H-120}' r='28' fill='url(#gpc)'/>")
    g.append(txt(330,H-112,"+",TXT,30,'400','middle'))
    g.append(navbar("Finance"))
    return frame("".join(g))

# ---------------- SPORT ----------------
def sport():
    g=[appbar("Sport")]
    # motivation quote
    g.append(rrect(20,80,350,56,16,CARD,PRIM,1))
    g.append(f"<rect x='20' y='80' width='4' height='56' rx='2' fill='url(#gpc)'/>")
    g.append(txt(40,106,"„Disziplin schlägt Motivation.“",SEC,13,'600'))
    g.append(txt(40,124,"— dein Jarvis",TXT2,11,'400'))
    # weekly ring
    g.append(rrect(20,150,350,120,16,CARD,BORDER,1))
    g.append(ring(85,210,42,0.66,PRIM,9))
    g.append(txt(85,206,"4/6",TXT,20,'800','middle'))
    g.append(txt(85,226,"Workouts",TXT2,10,'500','middle'))
    g.append(txt(160,188,"Diese Woche",TXT,15,'700'))
    g.append(txt(160,212,"4 von 6 Einheiten ✅",TXT2,12,'400'))
    g.append(txt(160,234,"\U0001F525 Streak: 12 Tage",WARN,13,'600'))
    g.append(txt(160,256,"320 Min gesamt",TXT2,12,'400'))
    # 7-day grid
    days=[("Mo",True),("Di",True),("Mi",False),("Do",True),("Fr",True),("Sa",False),("So",False)]
    x=24
    for d,done in days:
        g.append(rrect(x,286,42,52,12,PRIM if done else SURF,PRIM if done else BORDER,1,0.85 if done else 1))
        g.append(txt(x+21,308,d,TXT if done else TXT2,11,'600','middle'))
        g.append(txt(x+21,328,"✓" if done else "·",TXT if done else TXT2,14,'700','middle'))
        x+=50
    # recent workouts
    wk=[("\U0001F3C3","Laufen","40 Min · 420 kcal","Heute"),
        ("\U0001F3CB","Krafttraining","55 Min · 380 kcal","Gestern"),
        ("\U0001F6B4","Radfahren","60 Min · 510 kcal","Mo")]
    y=356
    for emo,t,sub,when in wk:
        g.append(rrect(20,y,350,56,14,CARD,BORDER,1))
        g.append(f"<circle cx='48' cy='{y+28}' r='18' fill='{SURF}'/>")
        g.append(txt(48,y+34,emo,TXT,16,'400','middle'))
        g.append(txt(78,y+25,t,TXT,14,'600'))
        g.append(txt(78,y+43,sub,TXT2,11,'400'))
        g.append(txt(350,y+33,when,SEC,11,'600','end'))
        y+=66
    g.append(f"<circle cx='330' cy='{H-120}' r='28' fill='url(#gpc)'/>")
    g.append(txt(330,H-112,"+",TXT,28,'400','middle'))
    g.append(navbar("Sport"))
    return frame("".join(g))

screens={"1_login":login(),"2_chat":chat(),"3_notes":notes(),
         "4_goals":goals(),"5_finance":finance(),"6_sport":sport()}
for name,svg in screens.items():
    cairosvg.svg2png(bytestring=svg.encode(),write_to=f"{OUT}/{name}.png",
                     output_width=W*2,output_height=H*2)
    print(f"rendered {name}.png")
print("DONE")
