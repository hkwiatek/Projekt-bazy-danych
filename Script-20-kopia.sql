

CREATE TABLE placowki (
    id_placowki SERIAL PRIMARY KEY,
    miasto VARCHAR(50) NOT NULL,
    adres VARCHAR(100) NOT NULL
);

CREATE TABLE dzialy (
    id_dzialu SERIAL PRIMARY KEY,
    nazwa_dzialu VARCHAR(50) NOT NULL,
    id_placowki INT NOT NULL REFERENCES placowki(id_placowki) ON DELETE RESTRICT
);

CREATE TABLE stanowiska (
    id_stanowiska SERIAL PRIMARY KEY,
    nazwa_stanowiska VARCHAR(50) NOT NULL,
    min_pensja NUMERIC(10, 2) NOT NULL CHECK (min_pensja > 0)
);

CREATE TABLE pracownicy (
    id_pracownika SERIAL PRIMARY KEY,
    imie VARCHAR(50) NOT NULL,
    nazwisko VARCHAR(50) NOT NULL,
    pesel CHAR(11) UNIQUE NOT NULL CHECK (pesel ~ '^[0-9]{11}$'),
    data_urodzenia DATE NOT NULL,
    id_przelozonego INT REFERENCES pracownicy(id_pracownika) ON DELETE SET NULL,
    czy_aktywny BOOLEAN DEFAULT TRUE NOT NULL
);

CREATE TABLE umowy (
    id_umowy SERIAL PRIMARY KEY,
    id_pracownika INT NOT NULL REFERENCES pracownicy(id_pracownika) ON DELETE RESTRICT, 
    id_dzialu INT NOT NULL REFERENCES dzialy(id_dzialu) ON DELETE RESTRICT,
    id_stanowiska INT NOT NULL REFERENCES stanowiska(id_stanowiska) ON DELETE RESTRICT,
    data_od DATE NOT NULL,
    data_do DATE NOT NULL,
    pensja_brutto NUMERIC(10, 2) NOT NULL CHECK (pensja_brutto > 0),
    CONSTRAINT sprawdz_chronologie_umow CHECK (data_do >= data_od)
);

CREATE TABLE audyt_umow (
    id_audytu SERIAL PRIMARY KEY,
    id_umowy INT NOT NULL,
    stara_pensja NUMERIC(10, 2),
    nowa_pensja NUMERIC(10, 2),
    data_zmiany TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uzytkownik VARCHAR(50) DEFAULT CURRENT_USER
);

CREATE TABLE typy_nieobecnosci (
    id_typu SERIAL PRIMARY KEY,
    nazwa_typu VARCHAR(50) NOT NULL,
    czy_platny BOOLEAN DEFAULT TRUE
);

CREATE TABLE nieobecnosci (
    id_nieobecnosci SERIAL PRIMARY KEY,
    id_pracownika INT NOT NULL REFERENCES pracownicy(id_pracownika) ON DELETE CASCADE,
    id_typu INT NOT NULL REFERENCES typy_nieobecnosci(id_typu),
    data_od DATE NOT NULL,
    data_do DATE NOT NULL,
    CONSTRAINT sprawdz_chronologie_nieobecnosci CHECK (data_do >= data_od)
);

CREATE TABLE premie (
    id_premii SERIAL PRIMARY KEY,
    id_pracownika INT NOT NULL REFERENCES pracownicy(id_pracownika) ON DELETE RESTRICT, 
    data_przyznania DATE NOT NULL DEFAULT CURRENT_DATE,
    kwota NUMERIC(10, 2) NOT NULL CHECK (kwota > 0),
    opis VARCHAR(255)
);


CREATE INDEX idx_pracownicy_przelozony ON pracownicy(id_przelozonego);
CREATE INDEX idx_umowy_pracownik ON umowy(id_pracownika);
CREATE INDEX idx_umowy_dzial ON umowy(id_dzialu);
CREATE INDEX idx_umowy_stanowisko ON umowy(id_stanowiska);
CREATE INDEX idx_nieobecnosci_pracownik ON nieobecnosci(id_pracownika);
CREATE INDEX idx_premie_pracownik ON premie(id_pracownika);


INSERT INTO placowki (miasto, adres) VALUES 
('Warszawa', 'Al. Jerozolimskie 45 (Centrala)'),
('Gdańsk', 'Olivia Business Centre (Oddział)');

INSERT INTO dzialy (nazwa_dzialu, id_placowki) VALUES 
('Zarząd', 1), ('Kadry i Płace', 1), ('Księgowość', 2), ('IT', 2);

INSERT INTO stanowiska (nazwa_stanowiska, min_pensja) VALUES 
('Dyrektor HR', 12000.00), ('Główny Księgowy', 10000.00), ('Programista Java', 9000.00), ('Stażysta HR', 4000.00);


INSERT INTO pracownicy (imie, nazwisko, pesel, data_urodzenia, id_przelozonego) VALUES 
('Magdalena', 'Zalewska', '82071422333', '1982-07-14', NULL),
('Tomasz', 'Lewandowski', '88091155666', '1988-09-11', NULL), 
('Anna', 'Wiśniewska', '90012033444', '1990-01-20', 1),   
('Piotr', 'Kowalski', '99120112345', '1999-12-01', 1);   


INSERT INTO umowy (id_pracownika, id_dzialu, id_stanowiska, data_od, data_do, pensja_brutto) VALUES 
(1, 2, 1, '2020-01-01', '2030-12-31', 18500.00), -- Magda: Kadry, Dyrektor
(2, 3, 2, '2022-01-01', '2030-12-31', 12000.00), -- Tomek: Księgowość, Gł. Księgowy
(3, 4, 3, '2022-03-15', '2030-12-31', 14500.00), -- Ania: IT, Programista
(4, 2, 4, '2024-01-01', '2030-12-31', 4500.00);  -- Piotrek: Kadry, Stażysta

INSERT INTO typy_nieobecnosci (nazwa_typu, czy_platny) VALUES 
('Urlop Wypoczynkowy', TRUE), ('Chorobowe (L4)', TRUE), ('Urlop Bezpłatny', FALSE);

INSERT INTO nieobecnosci (id_pracownika, id_typu, data_od, data_do) VALUES 
(1, 1, '2024-02-01', '2024-02-14'),
(3, 2, '2024-04-10', '2024-04-15');

INSERT INTO premie (id_pracownika, data_przyznania, kwota, opis) VALUES 
(3, CURRENT_DATE, 3000.00, 'Premia za oddanie projektu'),
(2, CURRENT_DATE, 1500.00, 'Premia kwartalna');

CREATE OR REPLACE FUNCTION fn_sprawdz_kolizje_dat()
RETURNS TRIGGER AS $$
BEGIN 
    IF TG_TABLE_NAME = 'umowy' THEN 
        IF EXISTS (
            SELECT 1 FROM umowy 
            WHERE id_pracownika = NEW.id_pracownika 
            AND id_umowy != COALESCE(NEW.id_umowy, -1) 
            AND (NEW.data_od <= data_do AND NEW.data_do >= data_od)
        ) THEN
            RAISE EXCEPTION 'Błąd krytyczny: Pracownik posiada już umowę w tym terminie!';
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'nieobecnosci' THEN
        IF EXISTS (
            SELECT 1 FROM nieobecnosci 
            WHERE id_pracownika = NEW.id_pracownika 
            AND id_nieobecnosci != COALESCE(NEW.id_nieobecnosci, -1)
            AND (NEW.data_od <= data_do AND NEW.data_do >= data_od)
        ) THEN
            RAISE EXCEPTION 'Błąd krytyczny: Pracownik ma już zarejestrowaną nieobecność w tym terminie!';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_umowy_spojnosc 
BEFORE INSERT OR UPDATE ON umowy 
FOR EACH ROW EXECUTE FUNCTION fn_sprawdz_kolizje_dat(); 

CREATE TRIGGER trg_nieobecnosci_spojnosc
BEFORE INSERT OR UPDATE ON nieobecnosci
FOR EACH ROW EXECUTE FUNCTION fn_sprawdz_kolizje_dat();



CREATE OR REPLACE FUNCTION fn_wymus_min_pensje()
RETURNS TRIGGER AS $$
DECLARE
    v_min_pensja NUMERIC(10,2);
BEGIN
    SELECT min_pensja INTO v_min_pensja
    FROM stanowiska
    WHERE id_stanowiska = NEW.id_stanowiska;

    IF NEW.pensja_brutto < v_min_pensja THEN
        RAISE EXCEPTION 'Odmowa: Proponowana pensja (%) jest niższa niż minimum dla stanowiska (%)!', NEW.pensja_brutto, v_min_pensja;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sprawdz_min_pensje
BEFORE INSERT OR UPDATE ON umowy
FOR EACH ROW EXECUTE FUNCTION fn_wymus_min_pensje();



CREATE OR REPLACE FUNCTION fn_audytuj_pensje()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.pensja_brutto IS DISTINCT FROM NEW.pensja_brutto THEN
        INSERT INTO audyt_umow (id_umowy, stara_pensja, nowa_pensja)
        VALUES (NEW.id_umowy, OLD.pensja_brutto, NEW.pensja_brutto);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audyt_umow
AFTER UPDATE ON umowy
FOR EACH ROW EXECUTE FUNCTION fn_audytuj_pensje();



CREATE VIEW v_pracownicy_info AS
SELECT 
    p.id_pracownika,
    p.imie || ' ' || p.nazwisko AS pracownik,
    s.nazwa_stanowiska AS stanowisko,
    d.nazwa_dzialu AS dzial,
    pl.miasto AS lokalizacja
FROM pracownicy p
JOIN umowy u ON p.id_pracownika = u.id_pracownika AND CURRENT_DATE BETWEEN u.data_od AND u.data_do
JOIN stanowiska s ON u.id_stanowiska = s.id_stanowiska
JOIN dzialy d ON u.id_dzialu = d.id_dzialu
JOIN placowki pl ON d.id_placowki = pl.id_placowki;



CREATE VIEW v_pelna_lista_plac AS
SELECT 
    p.id_pracownika,
    p.imie || ' ' || p.nazwisko AS pracownik,
    u.pensja_brutto AS podstawa,
    COALESCE(SUM(pr.kwota), 0) AS suma_premii,
    u.pensja_brutto + COALESCE(SUM(pr.kwota), 0) AS do_wyplaty
FROM pracownicy p
JOIN umowy u ON p.id_pracownika = u.id_pracownika
LEFT JOIN premie pr ON p.id_pracownika = pr.id_pracownika 
    AND EXTRACT(MONTH FROM pr.data_przyznania) = EXTRACT(MONTH FROM CURRENT_DATE)
    AND EXTRACT(YEAR FROM pr.data_przyznania) = EXTRACT(YEAR FROM CURRENT_DATE)
WHERE CURRENT_DATE BETWEEN u.data_od AND u.data_do 
GROUP BY p.id_pracownika, p.imie, p.nazwisko, u.pensja_brutto;



CREATE VIEW v_struktura_organizacyjna AS
WITH RECURSIVE hierarchia AS (
    SELECT id_pracownika, imie, nazwisko, id_przelozonego, 1 AS poziom_w_hierarchii,
           CAST(imie || ' ' || nazwisko AS VARCHAR(500)) AS sciezka_zarzadzania
    FROM pracownicy WHERE id_przelozonego IS NULL AND czy_aktywny = TRUE
    
    UNION ALL
    
    SELECT p.id_pracownika, p.imie, p.nazwisko, p.id_przelozonego, h.poziom_w_hierarchii + 1,
           CAST(h.sciezka_zarzadzania || ' -> ' || p.imie || ' ' || p.nazwisko AS VARCHAR(500))
    FROM pracownicy p
    JOIN hierarchia h ON p.id_przelozonego = h.id_pracownika
    WHERE p.czy_aktywny = TRUE
)
SELECT * FROM hierarchia ORDER BY poziom_w_hierarchii, sciezka_zarzadzania;



CREATE VIEW v_ranking_placowy AS
SELECT 
    d.nazwa_dzialu,
    p.imie || ' ' || p.nazwisko AS pracownik,
    u.pensja_brutto,
    RANK() OVER (PARTITION BY u.id_dzialu ORDER BY u.pensja_brutto DESC) as ranga_w_dziale
FROM pracownicy p
JOIN umowy u ON p.id_pracownika = u.id_pracownika AND CURRENT_DATE BETWEEN u.data_od AND u.data_do
JOIN dzialy d ON u.id_dzialu = d.id_dzialu;



CREATE VIEW v_status_pracownikow AS
SELECT 
    p.imie || ' ' || p.nazwisko AS pracownik,
    d.nazwa_dzialu AS dzial,
    CASE 
        WHEN n.id_nieobecnosci IS NOT NULL THEN 'Nieobecny (' || tn.nazwa_typu || ')'
        ELSE 'W pracy'
    END AS status_obecnosci,
    n.data_do AS powrot_do_pracy
FROM pracownicy p
JOIN umowy u ON p.id_pracownika = u.id_pracownika AND CURRENT_DATE BETWEEN u.data_od AND u.data_do
JOIN dzialy d ON u.id_dzialu = d.id_dzialu
LEFT JOIN nieobecnosci n ON p.id_pracownika = n.id_pracownika 
    AND CURRENT_DATE BETWEEN n.data_od AND n.data_do
LEFT JOIN typy_nieobecnosci tn ON n.id_typu = tn.id_typu;



CREATE VIEW v_budzet_dzialow AS
SELECT 
    d.nazwa_dzialu,
    COUNT(DISTINCT p.id_pracownika) AS liczba_pracownikow,
    COALESCE(SUM(u.pensja_brutto), 0) AS miesieczny_koszt_pensji,
    ROUND((COALESCE(SUM(u.pensja_brutto), 0) / NULLIF(SUM(SUM(u.pensja_brutto)) OVER (), 0)) * 100, 2) AS procent_budzetu_firmy
FROM dzialy d
LEFT JOIN umowy u ON d.id_dzialu = u.id_dzialu AND CURRENT_DATE BETWEEN u.data_od AND u.data_do
LEFT JOIN pracownicy p ON u.id_pracownika = p.id_pracownika AND p.czy_aktywny = TRUE
GROUP BY d.id_dzialu, d.nazwa_dzialu;



CREATE VIEW v_raport_podwyzek AS
SELECT 
    a.data_zmiany::date AS data_zmiany,
    p.imie || ' ' || p.nazwisko AS pracownik,
    a.stara_pensja,
    a.nowa_pensja,
    a.nowa_pensja - a.stara_pensja AS kwota_podwyzki,
    ROUND(((a.nowa_pensja - a.stara_pensja) / a.stara_pensja) * 100, 2) AS procent_podwyzki,
    a.uzytkownik AS kto_zmienil
FROM audyt_umow a
JOIN umowy u ON a.id_umowy = u.id_umowy
JOIN pracownicy p ON u.id_pracownika = p.id_pracownika
WHERE a.nowa_pensja > a.stara_pensja
ORDER BY a.data_zmiany DESC;





DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'rola_dyrektor') THEN
        CREATE ROLE rola_dyrektor NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'rola_ksiegowosc') THEN
        CREATE ROLE rola_ksiegowosc NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'rola_stazysta') THEN
        CREATE ROLE rola_stazysta NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user_magda') THEN
        CREATE USER user_magda WITH PASSWORD 'SzefowaHR123';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user_tomek') THEN
        CREATE USER user_tomek WITH PASSWORD 'KasaKasa123';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user_piotrek') THEN
        CREATE USER user_piotrek WITH PASSWORD 'Stazysta123';
    END IF;
END
$$;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rola_dyrektor;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rola_dyrektor;

GRANT SELECT ON pracownicy, umowy, premie, nieobecnosci TO rola_ksiegowosc;
GRANT SELECT ON v_pelna_lista_plac TO rola_ksiegowosc;

GRANT SELECT ON v_pracownicy_info, placowki, dzialy, stanowiska TO rola_stazysta;

GRANT rola_dyrektor TO user_magda;    
GRANT rola_ksiegowosc TO user_tomek;  
GRANT rola_stazysta TO user_piotrek;