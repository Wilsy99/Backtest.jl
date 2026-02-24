struct CPCV
    n_labels::Int
    n_groups::Int
    n_test_groups::Int
    n_folds::Int
    base_length::Int
    remainder::Int

    function CPCV(n_labels::Int, n_groups::Int, n_test_groups::Int)
        _natural(n_labels)
        _natural(n_groups)
        n_groups >= n_test_groups ||
            throw(ArgumentError("n_groups must be >= n_test_groups"))

        n_folds = binomial(n_groups, n_test_groups)
        base_length, remainder = divrem(n_labels, n_groups)

        return new(n_labels, n_groups, n_test_groups, n_folds, base_length, remainder)
    end
end

function CPCV(n_labels; n_groups=6, n_test_groups=2)
    return CPCV(n_labels, n_groups, n_test_groups)
end

function get_group_idx_range(cpcv::CPCV, group_num::Int)
    # Logic: groups 1 to cpcvrem get (base + 1) elements
    # groups (cpcv.rem + 1) to n_groups get (base) elements

    base_len = cpcv.base_length
    rem = cpcv.remainder

    # Calculate how many "extra" remainder bits were used before this group
    rem_used_before = min(group_num - 1, rem)

    start_idx = (group_num - 1) * base_len + rem_used_before + 1

    # Does this specific group get an extra bit?
    extra = group_num <= rem
    end_idx = start_idx + base_len + extra - 1

    return start_idx:end_idx
end

function get_fold_test_group_mask(cpcv::CPCV, fold_num::Int)
    n_groups = cpcv.n_groups
    k = cpcv.n_test_groups

    n = n_groups - 1
    k = k
    group_id = 1

    target_dist = cpcv.n_folds - fold_num + 1

    test_group_mask = falses(n_groups)

    for _ in 1:k
        # Calculate the size of the "Exclude this group" block (the tail)
        binom = binomial(n, k)

        # WHILE the tail is large enough to contain our target distance...
        while binom >= target_dist
            # Move to the next group and shrink the tail size
            n -= 1
            group_id += 1
            binom = binomial(n, k)
        end

        # If the tail is too small, the group_id MUST be in the set
        test_group_mask[group_id] = true

        # Prepare for the next pick (move one step right in the set)
        n -= 1
        group_id += 1
        k -= 1
        target_dist -= binom
    end

    return test_group_mask
end