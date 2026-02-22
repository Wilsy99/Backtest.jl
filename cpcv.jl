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
    current_extra = group_num <= rem
    end_idx = start_idx + base_len + current_extra - 1

    return start_idx:end_idx
end

function get_fold_test_groups(cpcv::CPCV, fold_num::Int)

    # Switch to 0-indexed for the math logic
    idx = fold_num - 1
    k = cpcv.n_test_groups
    n = cpcv.n_groups

    test_groups = Vector{Int}(undef, k)

    # We use a greedy approach to find the combination lexicographically
    # We start from the highest possible group number and work backwards
    current_n = n - 1
    for i in k:-1:1
        # Find the largest 'current_n' such that binomial(current_n, i) <= idx
        while binomial(current_n, i) > idx
            current_n -= 1
        end

        # In lexicographic order, this translates to our group ID
        # The +1 maps it back to Julia's 1-based indexing
        test_groups[k - i + 1] = n - current_n
        idx -= binomial(current_n, i)
    end

    return sort(test_groups)
end