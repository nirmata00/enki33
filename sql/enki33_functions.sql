-- Version: 1.3  
-- Date: 2024-02-07  
-- Description: Functions, triggers, views and initial data  

-- 1. Vista Materializada para Resumen de Período  
CREATE MATERIALIZED VIEW public.period_summary AS  
WITH period_transactions AS (  
    SELECT   
        p.id AS period_id,  
        p.description AS period_description,  
        p.from_date,  
        p.to_date,  
        t.organization,  
        t.transaction_type,  
        COALESCE(SUM(CASE WHEN tt.name = 'INGRESO' THEN t.amount ELSE 0 END), 0) as total_income,  
        COALESCE(SUM(CASE WHEN tt.name = 'EGRESO' THEN t.amount ELSE 0 END), 0) as total_expenses,  
        COALESCE(SUM(CASE WHEN tt.name = 'TRANSFERENCIA' THEN t.amount ELSE 0 END), 0) as total_transfers  
    FROM public.period p  
    LEFT JOIN public.transaction_period tp ON p.id = tp.period  
    LEFT JOIN public.transaction t ON tp.transaction = t.id  
    LEFT JOIN public.transaction_type tt ON t.transaction_type = tt.id  
    GROUP BY p.id, p.description, p.from_date, p.to_date, t.organization, t.transaction_type  
)  
SELECT   
    period_id,  
    period_description,  
    from_date,  
    to_date,  
    organization,  
    total_income,  
    total_expenses,  
    total_transfers,  
    (total_income - total_expenses) as net_balance,  
    (total_income * 0.55) as nec_budget,  
    (total_income * 0.10) as play_budget,  
    (total_income * 0.10) as ltss_budget,  
    (total_income * 0.10) as edu_budget,  
    (total_income * 0.10) as ffa_budget,  
    (total_income * 0.05) as give_budget  
FROM period_transactions;  

-- 2. Funciones y Triggers  
CREATE OR REPLACE FUNCTION update_modified_at()  
RETURNS TRIGGER AS $  
BEGIN  
    NEW.modified_at = CURRENT_TIMESTAMP;  
    RETURN NEW;  
END;  
$ LANGUAGE plpgsql;  

-- Función para calcular la próxima fecha de pago  
CREATE OR REPLACE FUNCTION calculate_next_payment_date(  
    p_payment_day smallint,  
    p_current_date date DEFAULT CURRENT_DATE  
)  
RETURNS date AS $  
DECLARE  
    v_next_date date;  
BEGIN  
    v_next_date := date_trunc('month', p_current_date) + (p_payment_day - 1) * interval '1 day';  

    IF v_next_date <= p_current_date THEN  
        v_next_date := v_next_date + interval '1 month';  
    END IF;  

    IF extract(day from v_next_date) != p_payment_day THEN  
        v_next_date := date_trunc('month', v_next_date) + interval '1 month' - interval '1 day';  
    END IF;  

    RETURN v_next_date;  
END;  
$ LANGUAGE plpgsql;  

-- Función para calcular la fecha de corte  
CREATE OR REPLACE FUNCTION calculate_cut_date(  
    p_cut_day smallint,  
    p_current_date date DEFAULT CURRENT_DATE  
)  
RETURNS date AS $  
DECLARE  
    v_next_date date;  
BEGIN  
    v_next_date := date_trunc('month', p_current_date) + (p_cut_day - 1) * interval '1 day';  

    IF v_next_date <= p_current_date THEN  
        v_next_date := v_next_date + interval '1 month';  
    END IF;  

    IF extract(day from v_next_date) != p_cut_day THEN  
        v_next_date := date_trunc('month', v_next_date) + interval '1 month' - interval '1 day';  
    END IF;  

    RETURN v_next_date;  
END;  
$ LANGUAGE plpgsql;  

-- Función para calcular la próxima fecha de ejecución de transacciones recurrentes  
CREATE OR REPLACE FUNCTION calculate_next_execution_date(  
    p_start_date date,  
    p_frequency interval,  
    p_execution_day smallint,  
    p_last_execution_date date DEFAULT NULL  
)  
RETURNS date AS $  
DECLARE  
    v_next_date date;  
    v_base_date date;  
BEGIN  
    v_base_date := COALESCE(p_last_execution_date, p_start_date);  
    v_next_date := v_base_date + p_frequency;  

    IF p_execution_day IS NOT NULL THEN  
        v_next_date := date_trunc('month', v_next_date) + (p_execution_day - 1) * interval '1 day';  

        IF v_next_date <= v_base_date THEN  
            v_next_date := v_next_date + interval '1 month';  
        END IF;  

        IF extract(day from v_next_date) != p_execution_day THEN  
            v_next_date := date_trunc('month', v_next_date) + interval '1 month' - interval '1 day';  
        END IF;  
    END IF;  

    RETURN v_next_date;  
END;  
$ LANGUAGE plpgsql;  

-- Trigger para actualizar fechas de cuenta  
CREATE OR REPLACE FUNCTION update_account_payment_dates()  
RETURNS TRIGGER AS $  
DECLARE  
    v_account_type_code varchar(20);  
BEGIN  
    SELECT code INTO v_account_type_code  
    FROM account_type  
    WHERE id = NEW.account_type;  

    IF v_account_type_code IN ('CREDIT_CARD', 'LOAN') THEN  
        IF NEW.payment_day IS NOT NULL THEN  
            NEW.next_payment_date := calculate_next_payment_date(NEW.payment_day);  
        END IF;  

        IF v_account_type_code = 'LOAN' AND NEW.loan_start_date IS NOT NULL AND NEW.loan_term_months IS NOT NULL THEN  
            NEW.loan_end_date := NEW.loan_start_date + (NEW.loan_term_months * interval '1 month');  
        END IF;  
    END IF;  

    RETURN NEW;  
END;  
$ LANGUAGE plpgsql;  

-- Trigger para actualizar fechas de transacciones recurrentes  
CREATE OR REPLACE FUNCTION update_recurring_transaction_dates()  
RETURNS TRIGGER AS $  
BEGIN  
    IF TG_OP = 'INSERT' THEN  
        NEW.next_execution_date := calculate_next_execution_date(  
            NEW.start_date,  
            NEW.frequency,  
            NEW.execution_day  
        );  
    ELSIF TG_OP = 'UPDATE' AND NEW.last_execution_date IS NOT NULL THEN  
        NEW.next_execution_date := calculate_next_execution_date(  
            NEW.start_date,  
            NEW.frequency,  
            NEW.execution_day,  
            NEW.last_execution_date  
        );  
        NEW.execution_count := COALESCE(NEW.execution_count, 0) + 1;  

        IF NEW.max_executions IS NOT NULL AND NEW.execution_count >= NEW.max_executions THEN  
            NEW.status := 'CANCELLED';  
        END IF;  
    END IF;  

    RETURN NEW;  
END;  
$ LANGUAGE plpgsql;  

-- Función para refrescar el resumen del período  
CREATE OR REPLACE FUNCTION refresh_period_summary()  
RETURNS TRIGGER AS $  
BEGIN  
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.period_summary;  
    RETURN NULL;  
END;  
$ LANGUAGE plpgsql;  

-- 3. Aplicar triggers  
CREATE TRIGGER set_modified_at  
    BEFORE UPDATE ON public.account  
    FOR EACH ROW  
    EXECUTE FUNCTION update_modified_at();  

CREATE TRIGGER trigger_update_account_dates  
    BEFORE INSERT OR UPDATE ON public.account  
    FOR EACH ROW  
    EXECUTE FUNCTION update_account_payment_dates();  

CREATE TRIGGER trigger_update_recurring_dates  
    BEFORE INSERT OR UPDATE ON public.recurring_transaction  
    FOR EACH ROW  
    EXECUTE FUNCTION update_recurring_transaction_dates();  

CREATE TRIGGER trigger_refresh_period_summary  
    AFTER INSERT OR UPDATE OR DELETE ON public.transaction  
    FOR EACH STATEMENT  
    EXECUTE FUNCTION refresh_period_summary();  

-- 4. Datos Iniciales  
-- Datos iniciales para account_type  
INSERT INTO public.account_type (name, code, description, requires_payment_info) VALUES  
('Cuenta de Débito', 'DEBIT', 'Cuenta bancaria regular', false),  
('Tarjeta de Crédito', 'CREDIT_CARD', 'Tarjeta de crédito con fecha de corte y pago', true),  
('Préstamo', 'LOAN', 'Préstamo con pagos mensuales', true),  
('Cuenta de Ahorro', 'SAVINGS', 'Cuenta para ahorros', false),  
('Inversión', 'INVESTMENT', 'Cuenta de inversiones', false),  
('Efectivo', 'CASH', 'Dinero en efectivo', false);  

-- Datos iniciales para budget_jar  
INSERT INTO public.budget_jar (code, name, description, percentage) VALUES  
('NEC', 'Necesidades Básicas', 'Gastos esenciales de vida diaria', 55),  
('PLAY', 'Diversión y Ocio', 'Entretenimiento y disfrute', 10),  
('LTSS', 'Ahorros a Largo Plazo', 'Metas a largo plazo y emergencias', 10),  
('EDU', 'Educación Financiera', 'Inversión en crecimiento personal', 10),  
('FFA', 'Inversiones', 'Libertad financiera', 10),  
('GIVE', 'Donaciones', 'Contribuciones y ayuda', 5);  

-- Datos iniciales para transaction_type  
INSERT INTO public.transaction_type (name, description) VALUES  
('INGRESO', 'Entrada de dinero'),  
('EGRESO', 'Salida de dinero'),  
('TRANSFERENCIA', 'Movimiento entre cuentas');  

-- Datos iniciales para transaction_medium  
INSERT INTO public.transaction_medium (name, description) VALUES  
('EFECTIVO', 'Pago en efectivo'),  
('TARJETA_CREDITO', 'Pago con tarjeta de crédito'),  
('TARJETA_DEBITO', 'Pago con tarjeta de débito'),  
('INTERNA', 'Transferencia interna entre cuentas');  

CREATE OR REPLACE FUNCTION public.record_balance_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.account_balance_history (
        account_id,
        previous_balance,
        new_balance,
        change_amount,
        transaction_id,
        transfer_id,
        change_type,
        changed_by,
        notes
    ) VALUES (
        NEW.id,
        OLD.balance,
        NEW.balance,
        NEW.balance - OLD.balance,
        NULL, -- Se actualizará mediante triggers específicos
        NULL, -- Se actualizará mediante triggers específicos
        'ADJUSTMENT', -- Valor por defecto, se actualizará mediante triggers específicos
        current_user::uuid, -- Asume que current_user es un UUID válido
        'Balance update'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Crear trigger para cambios en saldos de cuenta
CREATE TRIGGER track_balance_changes
AFTER UPDATE OF balance ON public.account
FOR EACH ROW
WHEN (OLD.balance IS DISTINCT FROM NEW.balance)
EXECUTE FUNCTION public.record_balance_change();

-- 5. Crear función para registrar cambios por transacciones
CREATE OR REPLACE FUNCTION public.record_transaction_balance_change()
RETURNS TRIGGER AS $$
DECLARE
    v_account_balance numeric(15, 2);
    v_new_balance numeric(15, 2);
BEGIN
    -- Obtener saldo actual
    SELECT balance INTO v_account_balance
    FROM public.account
    WHERE id = NEW.account;

    -- Calcular nuevo saldo basado en tipo de transacción
    IF NEW.is_expense THEN
        v_new_balance := v_account_balance - NEW.amount;
    ELSE
        v_new_balance := v_account_balance + NEW.amount;
    END IF;

    -- Registrar el cambio en el historial
    INSERT INTO public.account_balance_history (
        account_id,
        previous_balance,
        new_balance,
        change_amount,
        transaction_id,
        change_type,
        changed_by,
        notes
    ) VALUES (
        NEW.account,
        v_account_balance,
        v_new_balance,
        CASE WHEN NEW.is_expense THEN -NEW.amount ELSE NEW.amount END,
        NEW.id,
        'TRANSACTION',
        NEW.user_id,
        'Transaction ' || NEW.reference
    );

    -- Actualizar el saldo de la cuenta
    UPDATE public.account
    SET balance = v_new_balance
    WHERE id = NEW.account;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Crear trigger para nuevas transacciones
CREATE TRIGGER track_transaction_balance_changes
AFTER INSERT ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION public.record_transaction_balance_change();