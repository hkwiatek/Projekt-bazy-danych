-- TWORZENIE TABEL
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
    pesel CHAR(11) UNIQUE NOT null check (pesel ~ '^[0-9]{11}$'),
    data_urodzenia DATE NOT NULL,
    data_zatrudnienia DATE DEFAULT CURRENT_DATE,
    id_dzialu INT NOT NULL REFERENCES dzialy(id_dzialu) ON DELETE RESTRICT,
    id_stanowiska INT NOT NULL REFERENCES stanowiska(id_stanowiska) ON DELETE RESTRICT
);


CREATE TABLE umowy (
    id_umowy SERIAL PRIMARY KEY,
    id_pracownika INT NOT NULL REFERENCES pracownicy(id_pracownika) ON DELETE CASCADE,
    data_od DATE NOT NULL,
    data_do DATE NOT NULL,
    pensja_brutto NUMERIC(10, 2) NOT NULL CHECK (pensja_brutto > 0),
    CONSTRAINT sprawdz_chronologie_umow CHECK (data_do >= data_od)
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
    id_pracownika INT NOT NULL REFERENCES pracownicy(id_pracownika) ON DELETE CASCADE,
    data_przyznania DATE NOT NULL DEFAULT CURRENT_DATE,
    kwota NUMERIC(10, 2) NOT NULL CHECK (kwota > 0),
    opis VARCHAR(255)
);


-- FUNKCJE


CREATE OR REPLACE FUNCTION fn_sprawdz_kolizje_dat()
RETURNS TRIGGER AS $$
BEGIN -- zaczynamy funkcje
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


--PERSPEKTYWY 

CREATE VIEW v_pracownicy_info AS
SELECT 
    p.id_pracownika,
    p.imie || ' ' || p.nazwisko AS pracownik,
    s.nazwa_stanowiska AS stanowisko,
    d.nazwa_dzialu AS dzial,
    pl.miasto AS lokalizacja
FROM pracownicy p
JOIN stanowiska s ON p.id_stanowiska = s.id_stanowiska
JOIN dzialy d ON p.id_dzialu = d.id_dzialu
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


-- FUNKCJE 2


CREATE OR REPLACE FUNCTION oblicz_staz_lat(p_id_pracownika INT)
RETURNS INT AS $$
DECLARE
    v_staz INT;
BEGIN
    SELECT EXTRACT(YEAR FROM age(CURRENT_DATE, data_zatrudnienia)) INTO v_staz
    FROM pracownicy
    WHERE id_pracownika = p_id_pracownika;
    
    RETURN v_staz;
END;
$$ LANGUAGE plpgsql;


-- WYMYŚLONE DANE


INSERT INTO placowki (miasto, adres) VALUES 
('Warszawa', 'Al. Jerozolimskie 45 (Centrala)'),
('Gdańsk', 'Olivia Business Centre (Oddział)');

INSERT INTO dzialy (nazwa_dzialu, id_placowki) VALUES 
('Zarząd', 1),
('Kadry i Płace', 1),
('Księgowość', 2),
('IT', 2);

INSERT INTO stanowiska (nazwa_stanowiska, min_pensja) VALUES 
('Dyrektor HR', 12000.00),
('Główny Księgowy', 10000.00),
('Programista Java', 9000.00),
('Stażysta HR', 4000.00);

INSERT INTO pracownicy (imie, nazwisko, pesel, data_urodzenia, data_zatrudnienia, id_dzialu, id_stanowiska) VALUES 
('Magdalena', 'Zalewska', '82071422333', '1982-07-14', '2015-05-01', 2, 1), -- Dyrektor
('Tomasz', 'Lewandowski', '88091155666', '1988-09-11', '2018-09-01', 3, 2), -- Księgowy
('Anna', 'Wiśniewska', '90012033444', '1990-01-20', '2022-03-15', 4, 3), -- Programistka
('Piotr', 'Kowalski', '99120112345', '1999-12-01', '2024-01-01', 2, 4); -- Stażysta

INSERT INTO umowy (id_pracownika, data_od, data_do, pensja_brutto) VALUES 
(1, '2020-01-01', '2030-12-31', 18500.00),
(2, '2022-01-01', '2025-12-31', 12000.00),
(3, '2022-03-15', '2026-12-31', 14500.00),
(4, '2024-01-01', '2024-06-30', 4300.00);

INSERT INTO typy_nieobecnosci (nazwa_typu, czy_platny) VALUES 
('Urlop Wypoczynkowy', TRUE), ('Chorobowe (L4)', TRUE), ('Urlop Bezpłatny', FALSE);

INSERT INTO nieobecnosci (id_pracownika, id_typu, data_od, data_do) VALUES 
(1, 1, '2024-02-01', '2024-02-14'),
(3, 2, '2024-04-10', '2024-04-15');

INSERT INTO premie (id_pracownika, data_przyznania, kwota, opis) VALUES 
(3, CURRENT_DATE, 3000.00, 'Premia za oddanie projektu'),
(2, CURRENT_DATE, 1500.00, 'Premia kwartalna');

-- UPRAWNIENIA I ROLE


-- ZABEZPIECZENIE 
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



-- Dyrektor ma pełną władzę nad wszystkimi tabelami i sekwencjami
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rola_dyrektor;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rola_dyrektor;

--Księgowość: Może odczytywać dane płacowe, pracownicze i uruchamiać listę płac, ale nie zmienia danych
GRANT SELECT ON pracownicy, umowy, premie, nieobecnosci TO rola_ksiegowosc;
GRANT SELECT ON v_pelna_lista_plac TO rola_ksiegowosc;

-- Stażysta: Widzi tylko "wizytówki" pracowników i strukturę (nie ma w ogóle praw do tabel z pensjami/premiami)
GRANT SELECT ON v_pracownicy_info, placowki, dzialy, stanowiska TO rola_stazysta;

GRANT rola_dyrektor TO user_magda;    
GRANT rola_ksiegowosc TO user_tomek;  
GRANT rola_stazysta TO user_piotrek;  

