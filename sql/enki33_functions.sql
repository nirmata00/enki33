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


-- Trigger function para mantener el histórico de cambios en subcategorías
CREATE OR REPLACE FUNCTION public.track_subcategory_changes()
RETURNS TRIGGER AS $
BEGIN
    IF (OLD.category_id != NEW.category_id OR OLD.budget_jar_id != NEW.budget_jar_id) THEN
        INSERT INTO public.sub_category_history (
            sub_category_id,
            old_category_id,
            new_category_id,
            old_budget_jar_id,
            new_budget_jar_id,
            change_type
        ) VALUES (
            NEW.id,
            OLD.category_id,
            NEW.category_id,
            OLD.budget_jar_id,
            NEW.budget_jar_id,
            CASE 
                WHEN OLD.category_id != NEW.category_id AND OLD.budget_jar_id != NEW.budget_jar_id THEN 'BOTH'
                WHEN OLD.category_id != NEW.category_id THEN 'CATEGORY_CHANGE'
                ELSE 'JAR_CHANGE'
            END
        );
    END IF;
    RETURN NEW;
END;
$ LANGUAGE plpgsql;

-- Trigger para actualizar presupuestos cuando cambia el ingreso del período
CREATE OR REPLACE FUNCTION update_jar_budgets_for_period()
RETURNS TRIGGER AS $
BEGIN
    -- Actualizar o insertar presupuestos para cada jarra
    INSERT INTO public.jar_period_budget (period_id, budget_jar_id, calculated_amount)
    SELECT 
        NEW.period_id,
        bj.id,
        (NEW.total_income * (bj.percentage / 100))::numeric(15,2)
    FROM public.budget_jar bj
    ON CONFLICT (period_id, budget_jar_id) 
    DO UPDATE SET 
        calculated_amount = (NEW.total_income * (budget_jar.percentage / 100))::numeric(15,2);
    
    RETURN NEW;
END;
$ LANGUAGE plpgsql;

-- Crear triggers
CREATE TRIGGER track_subcategory_changes_trigger
AFTER UPDATE ON public.sub_category
FOR EACH ROW
EXECUTE FUNCTION public.track_subcategory_changes();

CREATE TRIGGER update_jar_budgets_trigger
AFTER INSERT OR UPDATE ON public.period_income
FOR EACH ROW
EXECUTE FUNCTION update_jar_budgets_for_period();

CREATE OR REPLACE FUNCTION check_period_status()
RETURNS TRIGGER AS $
DECLARE
    v_period_id uuid;
    v_is_closed boolean;
BEGIN
    -- Obtener el período correspondiente a la fecha de la transacción
    SELECT id, is_closed INTO v_period_id, v_is_closed
    FROM public.period
    WHERE NEW.date BETWEEN from_date AND to_date;

    IF v_is_closed THEN
        RAISE EXCEPTION 'No se pueden modificar transacciones en un período cerrado';
    END IF;

    -- Asignar automáticamente la transacción al período
    INSERT INTO public.transaction_period (transaction, period)
    VALUES (NEW.id, v_period_id);

    RETURN NEW;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER check_period_status_trigger
AFTER INSERT OR UPDATE ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION check_period_status();

CREATE OR REPLACE FUNCTION validate_jar_budget()
RETURNS TRIGGER AS $
DECLARE
    v_jar_id uuid;
    v_period_id uuid;
    v_budget numeric(15,2);
    v_spent numeric(15,2);
BEGIN
    -- Solo validar gastos
    IF NOT NEW.is_expense THEN
        RETURN NEW;
    END IF;

    -- Obtener la jarra de la subcategoría
    SELECT budget_jar_id INTO v_jar_id
    FROM public.sub_category
    WHERE id = NEW.sub_category;

    -- Obtener el período
    SELECT id INTO v_period_id
    FROM public.period
    WHERE NEW.date BETWEEN from_date AND to_date;

    -- Obtener presupuesto asignado
    SELECT calculated_amount INTO v_budget
    FROM public.jar_period_budget
    WHERE budget_jar_id = v_jar_id AND period_id = v_period_id;

    -- Calcular gastos actuales
    SELECT COALESCE(SUM(t.amount), 0) INTO v_spent
    FROM public.transaction t
    JOIN public.sub_category sc ON t.sub_category = sc.id
    WHERE sc.budget_jar_id = v_jar_id
    AND t.is_expense = true
    AND t.id != NEW.id
    AND t.date BETWEEN (SELECT from_date FROM public.period WHERE id = v_period_id)
                   AND (SELECT to_date FROM public.period WHERE id = v_period_id);

    IF (v_spent + NEW.amount) > v_budget THEN
        RAISE EXCEPTION 'El gasto excede el presupuesto disponible en la jarra. Disponible: %, Gasto: %', 
            (v_budget - v_spent), NEW.amount;
    END IF;

    RETURN NEW;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER validate_jar_budget_trigger
BEFORE INSERT OR UPDATE ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION validate_jar_budget();

CREATE OR REPLACE FUNCTION recalculate_period_totals(p_period_id uuid)
RETURNS void AS $
BEGIN
    -- Actualizar period_income
    INSERT INTO public.period_income (period_id, total_income)
    SELECT 
        p_period_id,
        COALESCE(SUM(t.amount), 0) as total_income
    FROM public.transaction t
    JOIN public.transaction_period tp ON t.id = tp.transaction
    WHERE tp.period = p_period_id
    AND NOT t.is_expense
    ON CONFLICT (period_id) 
    DO UPDATE SET 
        total_income = EXCLUDED.total_income,
        modified_at = CURRENT_TIMESTAMP;

    -- Refrescar vista materializada
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.period_summary;
END;
$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_transfer_transaction()
RETURNS TRIGGER AS $
DECLARE
    v_transfer_type_id uuid;
BEGIN
    -- Obtener ID del tipo de transacción 'TRANSFERENCIA'
    SELECT id INTO v_transfer_type_id
    FROM public.transaction_type
    WHERE name = 'TRANSFERENCIA';

    -- Validar que las transferencias tengan cuenta origen y destino
    IF NEW.transaction_type = v_transfer_type_id THEN
        IF NEW.transfer_account_id IS NULL THEN
            RAISE EXCEPTION 'Las transferencias requieren una cuenta destino';
        END IF;
    END IF;

    RETURN NEW;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER validate_transfer_transaction_trigger
BEFORE INSERT OR UPDATE ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION validate_transfer_transaction();