-- Ejemplo de consulta para la pantalla de transacciones recurrentes
SELECT 
    rt.description,
    rt.amount,
    c.name as currency,
    rf.name as frequency,
    rt.next_execution_date,
    rt.cut_day,
    rt.payment_day,
    rt.status,
    o.name as organization,
    cat.name as category,
    sc.name as subcategory,
    rt.execution_count
FROM recurring_transaction rt
JOIN currency c ON rt.currency_id = c.id
JOIN recurrence_frequency rf ON rt.frequency_id = rf.id
JOIN organization o ON rt.organization_id = o.id
JOIN category cat ON rt.category = cat.id
JOIN sub_category sc ON rt.sub_category = sc.id
WHERE rt.is_active = true
ORDER BY rt.next_execution_date;

-- Vista materializada para análisis de variaciones
CREATE MATERIALIZED VIEW public.recurrent_transaction_variations AS
SELECT 
    t.recurrence_group_id,
    rg.description as recurrence_description,
    t.date,
    t.amount as actual_amount,
    t.scheduled_amount,
    t.amount_variation,
    CASE 
        WHEN t.scheduled_amount != 0 
        THEN ROUND((t.amount_variation / t.scheduled_amount) * 100, 2)
        ELSE NULL 
    END as variation_percentage,
    c.name as category_name,
    sc.name as subcategory_name,
    o.name as organization_name
FROM transaction t
JOIN recurrence_group rg ON t.recurrence_group_id = rg.id
JOIN category c ON t.category = c.id
JOIN sub_category sc ON t.sub_category = sc.id
JOIN organization o ON t.organization_id = o.id
WHERE t.is_recurrent = true
AND t.scheduled_amount IS NOT NULL;

-- Índice para la vista materializada
CREATE UNIQUE INDEX idx_recurrent_variations_unique 
ON public.recurrent_transaction_variations (recurrence_group_id, date);

-- Todas las transferencias de una cuenta
SELECT * FROM public.account_transfer
WHERE from_account_id = 'uuid-cuenta' OR to_account_id = 'uuid-cuenta';

-- Transferencias en un período
SELECT * FROM public.account_transfer
WHERE transfer_date BETWEEN '2023-01-01' AND '2023-12-31';

-- Transferencias con tipo de cambio
SELECT * FROM public.account_transfer
WHERE exchange_rate != 1.0;