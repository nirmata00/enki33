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