"""Builds the curated exercise catalog (German) from free-exercise-db (Unlicense).

Usage: python3 curate.py <exercises.json> <out_dir>
Writes <out_dir>/exercises.json and downloads images to <out_dir>/ExerciseImages/<id>_<n>.jpg
"""
import json, os, sys, urllib.request

SRC, OUT = sys.argv[1], sys.argv[2]
IMG_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

# id: (German name, group, increment kg, [cues])
CURATED = {
    # --- Beine ---
    "Leg_Press": ("Beinpresse", "Beine", 5.0, [
        "Rücken und Gesäß fest an die Lehne, Füße schulterbreit mittig auf die Platte.",
        "Kontrolliert ablassen, bis die Knie ca. 90° gebeugt sind – unterer Rücken bleibt an der Lehne.",
        "Über die ganze Fußsohle wegdrücken, Knie oben nicht ganz durchstrecken."]),
    "Hack_Squat": ("Hackenschmidt-Kniebeuge (Hack Squat)", "Beine", 5.0, [
        "Schultern unter die Polster, Rücken an die Lehne, Füße schulterbreit.",
        "Tief in die Hocke gehen, Knie zeigen in Richtung Fußspitzen.",
        "Aus den Fersen nach oben drücken, Spannung im Rumpf halten."]),
    "Smith_Machine_Squat": ("Kniebeuge an der Multipresse", "Beine", 5.0, [
        "Stange auf dem oberen Trapez, Füße leicht vor dem Körper.",
        "Hüfte nach hinten-unten, Brust bleibt aufrecht.",
        "Kraftvoll hochdrücken, Knie nicht nach innen fallen lassen."]),
    "Barbell_Squat": ("Kniebeuge (Langhantel)", "Beine", 2.5, [
        "Stange auf dem oberen Rücken, Füße schulterbreit, Zehen leicht nach außen.",
        "Rumpf fest, mindestens bis Oberschenkel parallel zum Boden absenken.",
        "Aus der ganzen Fußsohle hochdrücken, Rücken bleibt neutral."]),
    "Leg_Extensions": ("Beinstrecker", "Beine", 2.5, [
        "Kniegelenk auf Höhe der Drehachse, Polster knapp über dem Sprunggelenk.",
        "Beine vollständig strecken und oben kurz halten.",
        "Langsam ablassen, Gewicht nicht aufschlagen lassen."]),
    "Lying_Leg_Curls": ("Beinbeuger liegend", "Beine", 2.5, [
        "Bauch auf das Polster, Polster knapp über den Fersen, Knie knapp über der Bankkante.",
        "Fersen Richtung Gesäß ziehen, Hüfte bleibt auf dem Polster.",
        "Kontrolliert zurück, Beine unten nicht ganz ablegen."]),
    "Seated_Leg_Curl": ("Beinbeuger sitzend", "Beine", 2.5, [
        "Knie auf Höhe der Drehachse, Oberschenkelpolster fest schließen.",
        "Unterschenkel kraftvoll nach unten-hinten ziehen.",
        "Langsam zurückführen, voller Bewegungsumfang."]),
    "Romanian_Deadlift": ("Rumänisches Kreuzheben", "Beine", 2.5, [
        "Stange schulterbreit greifen, Knie leicht gebeugt.",
        "Hüfte nach hinten schieben, Stange nah am Bein nach unten führen – Rücken gerade.",
        "Wenn die Beinrückseite gut gedehnt ist, Hüfte nach vorn strecken."]),
    "Barbell_Hip_Thrust": ("Hip Thrust", "Beine", 5.0, [
        "Oberer Rücken an der Bankkante, Stange (gepolstert) auf der Hüfte.",
        "Hüfte nach oben strecken, bis Oberkörper und Oberschenkel eine Linie bilden.",
        "Oben Gesäß anspannen, kontrolliert absenken."]),
    "Dumbbell_Lunges": ("Ausfallschritte (Kurzhantel)", "Beine", 2.0, [
        "Kurzhanteln seitlich halten, großer Schritt nach vorn.",
        "Hinteres Knie Richtung Boden senken, Oberkörper aufrecht.",
        "Über die vordere Ferse zurückdrücken, Seiten abwechseln."]),
    "Thigh_Abductor": ("Abduktoren-Maschine (Beine auseinander)", "Beine", 5.0, [
        "Aufrecht sitzen, Polster an der Außenseite der Knie.",
        "Beine kontrolliert nach außen drücken.",
        "Langsam zurück, Gewichte nicht aufschlagen lassen."]),
    "Thigh_Adductor": ("Adduktoren-Maschine (Beine zusammen)", "Beine", 5.0, [
        "Aufrecht sitzen, Polster an der Innenseite der Knie.",
        "Beine kontrolliert zusammendrücken.",
        "Langsam öffnen, bis eine leichte Dehnung spürbar ist."]),
    "Seated_Calf_Raise": ("Wadenheben sitzend", "Waden", 5.0, [
        "Fußballen auf die Kante, Polster auf den Oberschenkeln.",
        "Fersen so weit wie möglich nach oben drücken, kurz halten.",
        "Tief absenken, bis die Wade gedehnt ist."]),
    "Standing_Calf_Raises": ("Wadenheben stehend (Maschine)", "Waden", 5.0, [
        "Schultern unter die Polster, Fußballen auf der Kante.",
        "Auf die Zehenspitzen drücken, Knie fast gestreckt.",
        "Langsam tief in die Dehnung absenken."]),
    # --- Brust ---
    "Leverage_Chest_Press": ("Brustpresse (Maschine)", "Brust", 2.5, [
        "Sitz so einstellen, dass die Griffe auf Brustmitte sind.",
        "Schulterblätter zusammen, Griffe nach vorne wegdrücken.",
        "Kontrolliert zurück, bis die Brust gedehnt ist."]),
    "Machine_Bench_Press": ("Bankdrücken an der Maschine", "Brust", 2.5, [
        "Auf der Bank liegen, Griffe auf Brusthöhe.",
        "Gewicht nach oben drücken, Ellbogen ca. 45° vom Körper.",
        "Langsam absenken, Schultern bleiben hinten."]),
    "Leverage_Incline_Chest_Press": ("Schrägbank-Brustpresse (Maschine)", "Brust", 2.5, [
        "Griffe auf Höhe der oberen Brust.",
        "Schräg nach oben drücken, Brust raus.",
        "Kontrolliert zurückführen."]),
    "Smith_Machine_Bench_Press": ("Bankdrücken an der Multipresse", "Brust", 2.5, [
        "Bank so platzieren, dass die Stange über der unteren Brust läuft.",
        "Stange kontrolliert zur Brust senken.",
        "Kraftvoll hochdrücken, Schulterblätter zusammen."]),
    "Barbell_Bench_Press_-_Medium_Grip": ("Bankdrücken (Langhantel)", "Brust", 2.5, [
        "Etwas mehr als schulterbreit greifen, Schulterblätter zusammen, Füße fest am Boden.",
        "Stange kontrolliert zur unteren Brust senken.",
        "Nach oben drücken, Ellbogen nicht komplett abspreizen."]),
    "Dumbbell_Bench_Press": ("Bankdrücken (Kurzhantel)", "Brust", 2.0, [
        "Kurzhanteln auf Brusthöhe, Handflächen nach vorn.",
        "Nach oben drücken, oben leicht zusammenführen.",
        "Tief und kontrolliert absenken."]),
    "Incline_Dumbbell_Press": ("Schrägbankdrücken (Kurzhantel)", "Brust", 2.0, [
        "Bank auf ca. 30° stellen, Hanteln auf Höhe der oberen Brust.",
        "Schräg nach oben drücken.",
        "Langsam absenken bis zur Dehnung."]),
    "Butterfly": ("Butterfly (Maschine)", "Brust", 2.5, [
        "Sitz so einstellen, dass die Arme auf Brusthöhe sind.",
        "Arme in einem Bogen vor der Brust zusammenführen.",
        "Langsam öffnen, bis die Brust gedehnt ist."]),
    "Cable_Crossover": ("Kabelzug-Crossover", "Brust", 2.5, [
        "Mittig zwischen den Kabeltürmen, ein Fuß leicht vorn.",
        "Griffe in einem Bogen nach vorne-unten zusammenführen.",
        "Kontrolliert zurück, Ellbogen leicht gebeugt."]),
    # --- Rücken ---
    "Wide-Grip_Lat_Pulldown": ("Latzug breit", "Rücken", 2.5, [
        "Breit greifen, Oberschenkel unter die Polster.",
        "Stange zur oberen Brust ziehen, Brust raus, Ellbogen nach unten.",
        "Langsam nach oben führen, bis die Arme gestreckt sind."]),
    "Close-Grip_Front_Lat_Pulldown": ("Latzug eng", "Rücken", 2.5, [
        "Eng greifen, leicht nach hinten lehnen.",
        "Zur Brust ziehen, Schulterblätter nach unten-hinten.",
        "Kontrolliert zurück in die Streckung."]),
    "Pullups": ("Klimmzüge", "Rücken", 2.5, [
        "Etwas mehr als schulterbreit greifen, aus dem Hang starten.",
        "Hochziehen, bis das Kinn über der Stange ist.",
        "Kontrolliert ablassen. Gewicht = Zusatzgewicht (0 = Körpergewicht)."]),
    "Seated_Cable_Rows": ("Rudern am Kabelzug (sitzend)", "Rücken", 2.5, [
        "Füße an die Plattform, Knie leicht gebeugt, Rücken gerade.",
        "Griff zum Bauch ziehen, Schulterblätter zusammen.",
        "Langsam nach vorne, ohne den Rücken rund zu machen."]),
    "Leverage_Iso_Row": ("Rudermaschine", "Rücken", 2.5, [
        "Brust an das Polster, Griffe auf Schulterhöhe.",
        "Ellbogen nach hinten ziehen, Schulterblätter zusammen.",
        "Kontrolliert zurück in die Dehnung."]),
    "Leverage_High_Row": ("Hohes Rudern (Maschine)", "Rücken", 2.5, [
        "Oberschenkel fixieren, Griffe oben fassen.",
        "Schräg nach unten-hinten ziehen.",
        "Langsam zurück, Arme strecken."]),
    "One-Arm_Dumbbell_Row": ("Einarmiges Kurzhantelrudern", "Rücken", 2.0, [
        "Knie und Hand auf der Bank, Rücken parallel zum Boden.",
        "Hantel zur Hüfte ziehen, Ellbogen nah am Körper.",
        "Langsam ablassen, Seiten wechseln."]),
    "Rope_Straight-Arm_Pulldown": ("Überzüge am Kabel (gestreckte Arme)", "Rücken", 2.5, [
        "Seil am oberen Kabel, leicht nach vorne gebeugt.",
        "Mit fast gestreckten Armen in einem Bogen zu den Oberschenkeln ziehen.",
        "Kontrolliert zurück nach oben."]),
    "Hyperextensions_Back_Extensions": ("Rückenstrecker (Hyperextension)", "Rücken", 2.5, [
        "Hüfte am Polsterende, Füße fixiert.",
        "Oberkörper absenken, Rücken gerade.",
        "Bis zur Linie mit den Beinen hochkommen – nicht überstrecken."]),
    # --- Schultern ---
    "Leverage_Shoulder_Press": ("Schulterpresse (Maschine)", "Schultern", 2.5, [
        "Griffe auf Schulterhöhe, Rücken an der Lehne.",
        "Gerade nach oben drücken.",
        "Kontrolliert bis Schulterhöhe absenken."]),
    "Dumbbell_Shoulder_Press": ("Schulterdrücken (Kurzhantel)", "Schultern", 2.0, [
        "Aufrecht sitzen, Hanteln auf Schulterhöhe.",
        "Nach oben drücken, ohne ins Hohlkreuz zu gehen.",
        "Langsam zurück auf Schulterhöhe."]),
    "Side_Lateral_Raise": ("Seitheben (Kurzhantel)", "Schultern", 1.0, [
        "Hanteln seitlich, Ellbogen leicht gebeugt.",
        "Arme seitlich bis Schulterhöhe heben.",
        "Langsam absenken, nicht schwingen."]),
    "Cable_Seated_Lateral_Raise": ("Seitheben am Kabel", "Schultern", 1.25, [
        "Seitlich zum unteren Kabel, Griff mit der entfernten Hand.",
        "Arm seitlich bis Schulterhöhe heben.",
        "Kontrolliert zurück, Spannung halten."]),
    "Reverse_Machine_Flyes": ("Reverse Butterfly (hintere Schulter)", "Schultern", 2.5, [
        "Brust an das Polster, Griffe auf Schulterhöhe.",
        "Arme in einem Bogen nach hinten führen.",
        "Langsam zurück, Schultern unten lassen."]),
    "Face_Pull": ("Face Pulls (Seil)", "Schultern", 2.5, [
        "Seil am oberen Kabel auf Gesichtshöhe.",
        "Seil Richtung Stirn ziehen, Hände auseinander, Ellbogen hoch.",
        "Kontrolliert zurück."]),
    # --- Arme ---
    "Machine_Bicep_Curl": ("Bizepsmaschine", "Arme", 2.5, [
        "Oberarme flach auf das Polster, Ellbogen auf der Drehachse.",
        "Griffe Richtung Schultern beugen.",
        "Langsam fast ganz strecken."]),
    "Machine_Preacher_Curls": ("Scott-Curls (Maschine)", "Arme", 2.5, [
        "Achseln an die Polsterkante, Oberarme aufliegend.",
        "Griff nach oben beugen, kurz halten.",
        "Kontrolliert ablassen."]),
    "Dumbbell_Bicep_Curl": ("Bizeps-Curls (Kurzhantel)", "Arme", 1.0, [
        "Hanteln seitlich, Handflächen nach vorn.",
        "Beugen, Ellbogen bleiben am Körper.",
        "Langsam strecken, nicht schwingen."]),
    "Hammer_Curls": ("Hammer-Curls", "Arme", 1.0, [
        "Hanteln im Neutralgriff (Daumen oben).",
        "Beugen, Ellbogen fixiert.",
        "Kontrolliert ablassen."]),
    "Triceps_Pushdown_-_Rope_Attachment": ("Trizepsdrücken am Seil", "Arme", 2.5, [
        "Seil am oberen Kabel, Ellbogen am Körper.",
        "Nach unten strecken und Seilenden auseinanderziehen.",
        "Langsam zurück bis ca. 90° im Ellbogen."]),
    "Triceps_Pushdown": ("Trizepsdrücken am Kabel (Stange)", "Arme", 2.5, [
        "Stange am oberen Kabel, Ellbogen fest am Körper.",
        "Arme vollständig nach unten strecken.",
        "Kontrolliert zurück."]),
    "Cable_Rope_Overhead_Triceps_Extension": ("Trizepsstrecken über Kopf (Seil)", "Arme", 2.5, [
        "Mit dem Rücken zum Kabel, Seil hinter dem Kopf.",
        "Arme nach vorne-oben strecken, Ellbogen bleiben eng.",
        "Langsam in die Dehnung zurück."]),
    "Dip_Machine": ("Dip-Maschine", "Arme", 2.5, [
        "Aufrecht sitzen, Griffe seitlich.",
        "Griffe nach unten drücken, bis die Arme gestreckt sind.",
        "Kontrolliert zurück."]),
    # --- Bauch ---
    "Ab_Crunch_Machine": ("Bauchmaschine (Crunch)", "Bauch", 2.5, [
        "Füße fixieren, Griffe fassen.",
        "Oberkörper einrollen, Bauch anspannen – nicht mit den Armen ziehen.",
        "Langsam zurück."]),
    "Cable_Crunch": ("Kabel-Crunch (kniend)", "Bauch", 2.5, [
        "Kniend vor dem oberen Kabel, Seil neben dem Kopf.",
        "Oberkörper nach unten einrollen.",
        "Kontrolliert aufrichten, Hüfte bleibt ruhig."]),
    "Hanging_Leg_Raise": ("Hängendes Beinheben", "Bauch", 0.0, [
        "An der Stange hängen, Schultern aktiv.",
        "Beine kontrolliert nach oben heben.",
        "Langsam absenken, nicht schwingen. Gewicht = Zusatzgewicht."]),
    "Plank": ("Unterarmstütz (Plank)", "Bauch", 0.0, [
        "Unterarme unter den Schultern, Körper in einer Linie.",
        "Bauch und Gesäß anspannen.",
        "Halten. Wiederholungen = Sekunden."]),
}

EQUIP_DE = {"machine": "Maschine", "cable": "Kabelzug", "barbell": "Langhantel",
            "dumbbell": "Kurzhantel", "body only": "Körpergewicht", "other": "Sonstiges",
            "e-z curl bar": "SZ-Stange"}

data = {e["id"]: e for e in json.load(open(SRC))}
os.makedirs(os.path.join(OUT, "ExerciseImages"), exist_ok=True)
out = []
for eid, (name_de, group, inc, cues) in CURATED.items():
    e = data[eid]
    imgs = []
    for n, rel in enumerate(e["images"][:2]):
        fn = f"{eid}_{n}.jpg"
        dst = os.path.join(OUT, "ExerciseImages", fn)
        if not os.path.exists(dst):
            urllib.request.urlretrieve(IMG_BASE + rel, dst)
        imgs.append(fn.rsplit(".", 1)[0])
    out.append({
        "id": eid,
        "nameDE": name_de,
        "nameEN": e["name"],
        "group": group,
        "equipment": EQUIP_DE.get(e["equipment"] or "other", "Sonstiges"),
        "primaryMuscles": e["primaryMuscles"],
        "secondaryMuscles": e["secondaryMuscles"],
        "increment": inc,
        "cues": cues,
        "instructionsEN": e["instructions"],
        "images": imgs,
    })
json.dump(out, open(os.path.join(OUT, "exercises.json"), "w"), ensure_ascii=False, indent=1)
print(len(out), "exercises written")
