-- Limpiar datos existentes (si es necesario)
TRUNCATE TABLE public.budget_jar CASCADE;

-- Insertar los 6 frascos con sus porcentajes y descripciones detalladas
INSERT INTO public.budget_jar (name, description, percentage) 
VALUES 
    (
        'NEC',
        'Necesidades Básicas: Destinado a cubrir gastos esenciales de vida diaria como alquiler/hipoteca, ' ||
        'comida, transporte, servicios públicos, seguros y otras necesidades fundamentales. Este frasco ' ||
        'asegura la estabilidad de tus necesidades básicas.',
        55.00
    ),
    (
        'PLAY',
        'Diversión y Ocio: Reservado para actividades que generan felicidad y disfrute personal como salidas, ' ||
        'cenas, entretenimiento, hobbies y viajes. Este frasco es crucial para mantener una mentalidad de ' ||
        'abundancia y balance en la vida.',
        10.00
    ),
    (
        'LTSS',
        'Ahorros a Largo Plazo: Destinado a metas financieras de largo plazo como la compra de una casa, ' ||
        'un vehículo, vacaciones importantes o fondo de emergencia. Este dinero se reserva específicamente ' ||
        'para estos propósitos importantes.',
        10.00
    ),
    (
        'EDU',
        'Educación Financiera y Personal: Inversión en desarrollo personal y profesional, incluyendo cursos, ' ||
        'libros, seminarios, talleres y coaching. Este frasco representa el compromiso con el aprendizaje ' ||
        'continuo y el crecimiento personal.',
        10.00
    ),
    (
        'FFA',
        'Inversiones y Libertad Financiera: Dedicado a crear ingresos pasivos e inversiones como acciones, ' ||
        'bienes raíces, negocios y fondos de inversión. Este frasco está diseñado para generar más dinero ' ||
        'y construir libertad financiera.',
        10.00
    ),
    (
        'GIVE',
        'Donaciones y Contribuciones: Reservado para compartir la riqueza mediante donaciones caritativas, ' ||
        'regalos y ayuda a otros. Este frasco fomenta una mentalidad de abundancia y gratitud, ' ||
        'contribuyendo al bienestar general.',
        5.00
    );

-- Verificar que los porcentajes suman 100%
DO $
DECLARE
    total_percentage numeric;
BEGIN
    SELECT SUM(percentage) INTO total_percentage FROM public.budget_jar;
    
    IF total_percentage != 100.00 THEN
        RAISE EXCEPTION 'Error: Los porcentajes deben sumar 100%%. Total actual: %%', total_percentage;
    END IF;
END $;

-- Verificar la inserción
SELECT name, percentage, description 
FROM public.budget_jar 
ORDER BY percentage DESC;


-- Primero, crear la moneda undefined
INSERT INTO public.currency (
    code, 
    name, 
    symbol, 
    is_active
) VALUES (
    'UND', 
    'Undefined Currency', 
    'UND',
    true
);

-- Asegurar que existe la organización UNDEFINED
INSERT INTO public.organization (code, name, description, is_active, user_id)
VALUES (
    'UND', 
    'UNDEFINED', 
    'Placeholder organization for maintaining data integrity',
    true,
    (SELECT id FROM public.app_user LIMIT 1)  -- Asignar a un usuario administrador
)
ON CONFLICT (code) DO NOTHING;

-- Datos iniciales para frecuencias
INSERT INTO public.recurrence_frequency 
    (name, description, interval_value) 
VALUES 
    ('Diario', 'Se repite todos los días', interval '1 day'),
    ('Semanal', 'Se repite cada semana', interval '1 week'),
    ('Quincenal', 'Se repite cada 15 días', interval '15 days'),
    ('Mensual', 'Se repite cada mes', interval '1 month'),
    ('Bimestral', 'Se repite cada 2 meses', interval '2 months'),
    ('Trimestral', 'Se repite cada 3 meses', interval '3 months'),
    ('Semestral', 'Se repite cada 6 meses', interval '6 months'),
    ('Anual', 'Se repite cada año', interval '1 year');

-- 1. Primero, crear la jar UNDEFINED
INSERT INTO public.budget_jar (
    id,
    name,
    description,
    percentage,
    user_id
) VALUES (
    gen_random_uuid(), -- Genera un UUID aleatorio
    'UNDEFINED',
    'Jar por defecto para subcategorías sin jar asignada',
    0,
    (SELECT id FROM public.app_user LIMIT 1) -- Asignar a un usuario administrador
) ON CONFLICT (name) DO NOTHING;

-- Insertar registros UNDEFINED en las tablas necesarias
INSERT INTO public.category (name, description)
VALUES ('UNDEFINED', 'Categoría por defecto para transacciones huérfanas');

INSERT INTO public.sub_category (name, description, category_id, budget_jar_id)
VALUES ('UNDEFINED', 'Subcategoría por defecto para transacciones huérfanas', 
        (SELECT id FROM public.category WHERE name = 'UNDEFINED'),
        (SELECT id FROM public.budget_jar WHERE name = 'UNDEFINED'));

INSERT INTO public.transaction_type (name, description)
VALUES ('UNDEFINED', 'Tipo de transacción por defecto');

INSERT INTO public.transaction_medium (name, description)
VALUES ('UNDEFINED', 'Medio de transacción por defecto');